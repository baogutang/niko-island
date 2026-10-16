import Foundation

extension SessionHost {
    public static let kiroDesktop = SessionHost(name: "Kiro", bundleID: "dev.kiro.desktop")
}

/// Kiro keeps each session in a folder of its own,
/// `~/.kiro/sessions/<workspace>/sess_<id>/`: `session.json` (title, workspace,
/// model, times) and `messages.jsonl`, one record per line with a `payload.type`
/// (`turn_start`, `user`, `assistant`, `tool_call`, `tool_result`, `turn_end`,
/// `pending_interaction` / `interaction_resolved` around a permission prompt, …).
/// Both are read, never written; only the end of the record file is read. This
/// is how a Kiro session shows up without any hook.
public final class KiroSessions {
    public static let source = "kiro"
    static let tailBytes: UInt64 = 256 * 1024

    private struct Cached {
        var stamp: (Date, UInt64)
        var reading: ZCodeSessions.Reading
    }

    private let home: URL
    private var cache: [String: Cached] = [:]

    public init(home: URL) {
        self.home = home
    }

    var root: URL { home.appendingPathComponent(".kiro/sessions") }

    /// Sessions written to since `cutoff`, newest first.
    public func snapshots(since cutoff: Date, now: Date = Date(), limit: Int = 24) -> [TranscriptSnapshot] {
        let manager = FileManager.default
        var found: [(folder: URL, modified: Date, size: UInt64)] = []
        for workspace in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for folder in (try? manager.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil)) ?? []
            where folder.lastPathComponent.hasPrefix("sess_") {
                let messages = folder.appendingPathComponent("messages.jsonl")
                guard let attributes = try? manager.attributesOfItem(atPath: messages.path),
                      let modified = attributes[.modificationDate] as? Date, modified >= cutoff,
                      let size = (attributes[.size] as? NSNumber)?.uint64Value else { continue }
                found.append((folder, modified, size))
            }
        }
        found.sort { $0.modified > $1.modified }
        var seen: Set<String> = []
        var out: [TranscriptSnapshot] = []
        for item in found {
            guard out.count < limit else { break }
            let key = item.folder.path
            seen.insert(key)
            let reading: ZCodeSessions.Reading
            if let cached = cache[key], cached.stamp == (item.modified, item.size) {
                reading = cached.reading
            } else {
                guard let fresh = Self.read(folder: item.folder, modified: item.modified, size: item.size) else { continue }
                cache[key] = Cached(stamp: (item.modified, item.size), reading: fresh)
                reading = fresh
            }
            // Kiro writes its own housekeeping into a session whenever the app opens it:
            // what counts is when somebody last worked in it.
            guard reading.updated >= cutoff else { continue }
            var snapshot = ZCodeSessions.snapshot(reading, path: item.folder.appendingPathComponent("messages.jsonl").path, now: now)
            snapshot.key = SessionKey(source: Self.source, sessionID: reading.id)
            snapshot.host = .kiroDesktop
            out.append(snapshot)
        }
        cache = cache.filter { seen.contains($0.key) }
        return out
    }

    static func read(folder: URL, modified: Date, size: UInt64) -> ZCodeSessions.Reading? {
        let info = (try? Data(contentsOf: folder.appendingPathComponent("session.json"))).flatMap { try? JSONValue.parse($0) }
        let id = info?["id"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? folder.lastPathComponent
        var reading = ZCodeSessions.Reading(
            id: id, parentID: nil,
            cwd: (info?["workspacePaths"]?.arrayValue?.first ?? info?["rootPaths"]?.arrayValue?.first)?.stringValue,
            title: info?["title"]?.stringValue.flatMap(title), updated: modified, turn: .finished, desktop: true)
        reading.model = info?["modelId"]?.stringValue
        guard let handle = try? FileHandle(forReadingFrom: folder.appendingPathComponent("messages.jsonl")) else { return reading }
        defer { try? handle.close() }
        let start = size > tailBytes ? size - tailBytes : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }   // the first line was cut in half
        apply(lines.compactMap { try? JSONValue.parse(Data($0)) }, to: &reading)
        return reading
    }

    /// Walks the records in order: the last turn's state, the last prompt and the last reply.
    /// `updated` becomes the time of the last record that is work (a prompt, a reply, a
    /// turn starting or ending, a tool of the agent's), not Kiro's own housekeeping.
    static func apply(_ records: [JSONValue], to reading: inout ZCodeSessions.Reading) {
        var lastWork: Date?
        var housekeeping: Set<String> = []
        // A permission prompt Kiro is showing, until it says how it was answered.
        var asking: String?
        for record in records {
            guard let payload = record["payload"], let type = payload["type"]?.stringValue else { continue }
            let at = record["timestamp"]?.stringValue.flatMap(ISOTime.parse).map(Date.init(timeIntervalSince1970:))
            let isWork: Bool
            switch type {
            case "turn_start", "user", "assistant", "turn_end": isWork = true
            case "tool_call":
                isWork = payload["kind"]?.stringValue != "other"
                if !isWork, let id = payload["toolCallId"]?.stringValue { housekeeping.insert(id) }
            case "tool_result": isWork = !(payload["toolCallId"]?.stringValue.map(housekeeping.contains) ?? false)
            case "pending_interaction", "interaction_resolved": isWork = true
            default: isWork = false
            }
            if isWork, let at { lastWork = at }
            switch type {
            case "turn_start":
                reading.turn = .thinking
                reading.since = at
            case "user":
                if let text = payload["content"]?.stringValue, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    reading.lastPrompt = text
                    reading.lastReply = nil
                }
                reading.turn = .thinking
            case "assistant":
                if let text = payload["content"]?.stringValue, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    reading.lastReply = text.count > 600 ? String(text.prefix(600)) : text
                }
            case "tool_call":
                // Kiro's own housekeeping (kind "other", such as fetching its cloud settings) is not work worth naming.
                guard payload["kind"]?.stringValue != "other", let tool = payload["toolName"]?.stringValue else { continue }
                let input = payload["args"]?.objectValue
                if payload["status"]?.stringValue == "completed" {
                    reading.turn = .thinking
                } else {
                    reading.turn = .tool(Activity.forTool(tool, input: input))
                }
            case "pending_interaction":
                // Kiro asks in its own window (Allow, Always allow, Deny): the island can only say so.
                asking = payload["toolCallId"]?.stringValue ?? ""
                let what = payload["question"]?.stringValue.map { Activity.oneLine($0, limit: 96) }
                reading.turn = .attention(payload["interactionType"]?.stringValue == "tool_approval" || payload["interactionType"] == nil
                                          ? Activity(verb: "needs permission", detail: what.map(toolLabel))
                                          : Activity(verb: "has a question", detail: what))
                reading.since = at
            case "interaction_resolved":
                guard asking != nil, payload["toolCallId"]?.stringValue == asking || asking == "" else { continue }
                asking = nil
                reading.turn = .thinking
            case "turn_end":
                asking = nil
                reading.turn = .finished
                reading.since = at
            default:
                continue
            }
        }
        if let lastWork { reading.updated = min(reading.updated, lastWork) } else { reading.updated = .distantPast }
    }

    /// "remote/web_search" → "web_search": the tool, without where Kiro keeps it.
    static func toolLabel(_ question: String) -> String {
        guard !question.contains(" "), let last = question.split(separator: "/").last else { return question }
        return String(last)
    }

    private static func title(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Activity.oneLine(trimmed, limit: 120)
    }
}
