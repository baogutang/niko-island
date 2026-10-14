import Foundation

extension SessionHost {
    public static let zcodeDesktop = SessionHost(name: "ZCode", bundleID: "dev.zcode.app")
}

/// ZCode keeps its sessions in a SQLite database of its own
/// (`~/.zcode/cli/db/db.sqlite`: `session`, `message`, `part`), and the desktop
/// app keeps a list of its tasks next to it (`~/.zcode/v2/tasks-index.sqlite`).
/// Both are opened read-only; this is how a ZCode session shows up when it is
/// idle, was open before this app, or runs in the desktop app.
public final class ZCodeSessions {
    public static let source = "zcode"

    public static func databasePath(home: URL) -> String { ZCodeUsage.databasePath(home: home) }
    public static func taskIndexPath(home: URL) -> String { home.appendingPathComponent(".zcode/v2/tasks-index.sqlite").path }

    /// One session as the database describes it, before "how long has it been quiet" is applied.
    struct Reading: Equatable {
        var id: String
        var parentID: String?
        var cwd: String?
        var title: String?
        var updated: Date
        var lastPrompt: String?
        var lastReply: String?
        var turn: Turn
        var since: Date?
        var desktop = false
        var progress: TaskProgress?
        var model: String?
    }

    enum Turn: Equatable {
        case thinking
        case tool(Activity)
        case attention(Activity)
        case finished
    }

    private let home: URL
    private var db: SQLiteDB?
    private var tasks: SQLiteDB?
    private var cached: [Reading] = []
    private var version: (main: Int64, tasks: Int64, cutoffBucket: Int64) = (-1, -1, -1)
    /// After a failure the database is left alone for a while instead of being reopened every tick.
    private var retryAfter = Date.distantPast

    public init(home: URL) {
        self.home = home
    }

    deinit {
        db?.close()
        tasks?.close()
    }

    /// Sessions touched since `cutoff`. Never throws: a database that is missing,
    /// locked or changed shape simply yields nothing.
    public func snapshots(since cutoff: Date, now: Date = Date(), limit: Int = 24) -> [TranscriptSnapshot] {
        do {
            let path = Self.databasePath(home: home)
            return try readings(since: cutoff, now: now, limit: limit).map { Self.snapshot($0, path: path, now: now) }
        } catch {
            close()
            retryAfter = now.addingTimeInterval(20)
            return []
        }
    }

    private func close() {
        db?.close()
        db = nil
        tasks?.close()
        tasks = nil
        cached = []
        version = (-1, -1, -1)
    }

    private func dataVersion(_ db: SQLiteDB?) -> Int64 {
        guard let db, let row = try? db.query("PRAGMA data_version").first, case .integer(let value)? = row.first else { return -1 }
        return value
    }

    func readings(since cutoff: Date, now: Date, limit: Int) throws -> [Reading] {
        guard now >= retryAfter else { return [] }
        let path = Self.databasePath(home: home)
        guard FileManager.default.fileExists(atPath: path) else {
            close()
            return []
        }
        if db == nil { db = try SQLiteDB(path: path, readOnly: true) }
        let taskPath = Self.taskIndexPath(home: home)
        if tasks == nil, FileManager.default.fileExists(atPath: taskPath) { tasks = try? SQLiteDB(path: taskPath, readOnly: true) }
        guard let db else { return [] }

        // Nothing was written since the last look: what we read then still holds.
        let current = (dataVersion(db), dataVersion(tasks), Int64(cutoff.timeIntervalSince1970 / 60))
        if current == version { return cached }

        let rows = try db.query("""
            SELECT id, parent_id, directory, title, time_updated FROM session
            WHERE time_updated >= ? AND time_archived IS NULL ORDER BY time_updated DESC LIMIT ?
            """, [.integer(Int64(cutoff.timeIntervalSince1970 * 1000)), .integer(Int64(limit))])
        let hidden = hiddenTasks()
        var out: [Reading] = []
        for row in rows {
            guard let id = row[0].stringValue, !id.isEmpty, hidden[id] != true else { continue }
            var reading = Reading(id: id, parentID: row[1].stringValue, cwd: row[2].stringValue.flatMap(project),
                                  title: row[3].stringValue.flatMap(Self.title), updated: Self.date(row[4].doubleValue),
                                  turn: .finished, desktop: hidden[id] != nil)
            try read(session: id, into: &reading, db: db)
            reading.progress = progress(of: id, db: db)
            out.append(reading)
        }
        // A helper lives in the app its parent lives in.
        let desktop = Set(out.filter(\.desktop).map(\.id))
        for index in out.indices where !out[index].desktop {
            if let parent = out[index].parentID, desktop.contains(parent) { out[index].desktop = true }
        }
        cached = out
        version = current
        return out
    }

    /// Task id → whether the desktop app has it archived or deleted. A session
    /// that is in this list at all belongs to the desktop app.
    private func hiddenTasks() -> [String: Bool] {
        guard let tasks, let rows = try? tasks.query("SELECT task_id, archived, deleted FROM tasks ORDER BY updated_at DESC LIMIT 400") else { return [:] }
        var out: [String: Bool] = [:]
        for row in rows {
            guard let id = row[0].stringValue else { continue }
            out[id] = row[1].intValue != 0 || row[2].intValue != 0
        }
        return out
    }

    private func read(session id: String, into reading: inout Reading, db: SQLiteDB) throws {
        let messages = try db.query("SELECT id, data FROM message WHERE session_id = ? ORDER BY sequence DESC LIMIT 8", [.text(id)])
        var sawNewest = false
        var assistantsRead = 0
        for row in messages {
            guard let messageID = row[0].stringValue, let data = row[1].stringValue,
                  let message = (try? JSONValue.parse(Data(data.utf8)))?.objectValue else { continue }
            let role = message["role"]?.stringValue
            let created = message["time"]?["created"]?.doubleValue.map(Self.date)
            let completed = message["time"]?["completed"]?.doubleValue.map(Self.date)
            if role == "user" {
                // Notes the app writes into the conversation for itself are not something the user asked.
                if message["synthetic"]?.boolValue == true || message["visibility"]?.stringValue == "hidden" { continue }
                if !sawNewest {
                    sawNewest = true
                    reading.turn = .thinking
                    reading.since = created
                }
                if reading.lastPrompt == nil { reading.lastPrompt = try prompt(of: messageID, db: db) }
                if reading.lastPrompt != nil { break }
            } else if role == "assistant" {
                assistantsRead += 1
                if reading.model == nil { reading.model = (message["modelId"] ?? message["modelID"])?.stringValue }
                let parts = assistantsRead <= 3 ? try self.parts(of: messageID, db: db) : []
                if !sawNewest {
                    sawNewest = true
                    switch message["finish"]?.stringValue {
                    case "stop", "completed", "length", "error":
                        reading.turn = .finished
                        reading.since = completed ?? created
                    default:
                        // Still writing, or about to run the tools it asked for.
                        reading.turn = Self.turn(from: parts)
                        reading.since = nil
                    }
                }
                if reading.lastReply == nil {
                    reading.lastReply = parts.lazy.compactMap { part -> String? in
                        guard part["type"]?.stringValue == "text", part["synthetic"]?.boolValue != true else { return nil }
                        return part["text"]?.stringValue.flatMap(TranscriptText.reply)
                    }.first
                }
            }
        }
    }

    /// The steps ZCode keeps for a session in its `todo` table.
    private func progress(of id: String, db: SQLiteDB) -> TaskProgress? {
        guard let rows = try? db.query("SELECT content, status FROM todo WHERE session_id = ? ORDER BY position LIMIT 200", [.text(id)]), !rows.isEmpty else { return nil }
        return TaskProgress.from(items: rows.map { row in
            .object(JSONObject(["content": .string(row[0].stringValue ?? ""), "status": .string(row[1].stringValue ?? "")]))
        })
    }

    /// The parts of one message, newest first.
    private func parts(of messageID: String, db: SQLiteDB) throws -> [JSONObject] {
        try db.query("SELECT data FROM part WHERE message_id = ? ORDER BY sequence DESC LIMIT 16", [.text(messageID)]).compactMap { row in
            // A tool part carries the tool's whole output; only its head matters here.
            guard let data = row[0].stringValue else { return nil }
            return (try? JSONValue.parse(Data(data.utf8), skipping: ["output", "metadata"]))?.objectValue
        }
    }

    private func prompt(of messageID: String, db: SQLiteDB) throws -> String? {
        for row in try db.query("SELECT data FROM part WHERE message_id = ? ORDER BY sequence LIMIT 6", [.text(messageID)]) {
            guard let data = row[0].stringValue, let part = (try? JSONValue.parse(Data(data.utf8)))?.objectValue,
                  part["type"]?.stringValue == "text", part["synthetic"]?.boolValue != true,
                  let text = part["text"]?.stringValue.flatMap(TranscriptText.prompt) else { continue }
            return text
        }
        return nil
    }

    static func turn(from parts: [JSONObject]) -> Turn {
        for part in parts {
            switch part["type"]?.stringValue {
            case "tool":
                let status = part["state"]?["status"]?.stringValue
                guard status == "running" || status == "pending" else { return .thinking }      // it returned: back to the model
                let name = part["tool"]?.stringValue
                if name == "AskUserQuestion" { return .attention(Activity(verb: "has a question")) }
                if name == "Agent" || name == "Task" {
                    let input = part["state"]?["input"]
                    let who = (input?["subagent_type"] ?? input?["description"])?.stringValue
                    return .tool(Activity(verb: "delegating", detail: who.map { Activity.oneLine($0, limit: 64) }))
                }
                return .tool(Activity.forTool(name, input: part["state"]?["input"]?.objectValue))
            case "text", "reasoning", "step-start":
                return .thinking
            default:
                continue
            }
        }
        return .thinking
    }

    static func snapshot(_ reading: Reading, path: String, now: Date) -> TranscriptSnapshot {
        let quiet = now.timeIntervalSince(reading.updated)
        let stale = quiet > TranscriptText.staleAfter
        let phase: Session.Phase
        let activity: Activity
        switch reading.turn {
        case .finished: (phase, activity) = (.waiting, .waiting)
        case .thinking: (phase, activity) = stale ? (.waiting, .waiting) : (.working, .thinking)
        case .tool(let tool): (phase, activity) = stale ? (.waiting, .waiting) : (.working, tool)
        case .attention(let what): (phase, activity) = stale ? (.waiting, .waiting) : (.needsAttention, what)
        }
        var snapshot = TranscriptSnapshot(
            key: SessionKey(source: source, sessionID: reading.id), path: path, cwd: reading.cwd,
            host: reading.desktop ? .zcodeDesktop : nil, title: reading.title,
            firstPrompt: reading.lastPrompt, lastPrompt: reading.lastPrompt, lastReply: reading.lastReply,
            phase: phase, activity: activity, updatedAt: reading.updated, phaseSince: reading.since,
            isSubagent: reading.parentID != nil, parentID: reading.parentID)
        snapshot.progress = reading.progress
        snapshot.model = reading.model
        return snapshot
    }

    /// A session started without a project lives in ZCode's own scratch folder,
    /// which says nothing about what it is for.
    private func project(_ directory: String) -> String? {
        directory.hasPrefix(home.appendingPathComponent(".zcode").path + "/") ? nil : directory
    }

    /// A time ZCode wrote down. One that is not a time at all reads as the start of 1970, which
    /// makes the session too old to list, rather than a date that cannot be counted from.
    private static func date(_ value: Double) -> Date {
        ISOTime.date(value) ?? Date(timeIntervalSince1970: 0)
    }

    /// ZCode names a session after its first words until it has thought of something better.
    private static func title(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Activity.oneLine(trimmed, limit: 120)
    }
}
