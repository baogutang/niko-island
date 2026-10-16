import Foundation

/// What each agent did, day by day, counted from its hook events: sessions,
/// prompts and tool calls, and which tools. Token logs exist for only a few
/// agents; every connected agent sends events, so this is the one record that
/// covers them all. Only counts and tool names are kept: no prompt, no command,
/// no path. Kept for half a year.
public final class ActivityLedger: @unchecked Sendable {
    public static let retentionDays = 190
    /// Days shown on the long heatmap: 26 weeks.
    public static let heatmapDays = 182

    private let queue = DispatchQueue(label: "niko.activity", qos: .utility)
    private let path: URL
    private var db: SQLiteDB?
    private let calendar: Calendar
    private let clock: () -> Date

    // Waiting to be written, keyed "day|agent" and "day|agent|tool".
    private var counts: [String: (sessions: Int, prompts: Int, tools: Int)] = [:]
    private var toolCounts: [String: Int] = [:]
    /// Sessions already counted on a day, "day|agent|session".
    private var seenSessions: Set<String> = []
    private var seenDay = ""
    /// Tool calls already counted, by the agent's own call id; the oldest go first.
    private var seenCalls: Set<String> = []
    private var callOrder: [String] = []
    /// Sessions that announce a call before making it: their after-the-call events are not counted again.
    private var announcing: Set<String> = []
    private var flushScheduled = false
    private var pruned = false

    public init(path: URL, timeZone: TimeZone = .current, clock: @escaping () -> Date = Date.init) {
        self.path = path
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.clock = clock
    }

    public static func defaultPath(paths: NikoPaths) -> URL { paths.usageDir.appendingPathComponent("activity.sqlite") }

    // MARK: Counting

    /// Notes one event. Cheap; the write happens a moment later, off the main thread.
    public func record(_ event: AgentEvent) {
        let entry = Self.entry(for: event)
        let date = event.timestampMS > 0 ? event.date : clock()
        queue.async { [self] in
            add(entry, at: date)
            scheduleFlush()
        }
    }

    struct Entry: Equatable {
        var agent: String
        var session: String
        var prompt = false
        var tool: String?
        var callID: String?
        /// The event announces a call (PreToolUse) rather than reports one.
        var before = false
    }

    /// Events that are not a tool call, though some agents send them as one.
    static let notTools: Set<String> = ["afterAgentThought", "afterAgentResponse"]

    static func entry(for event: AgentEvent) -> Entry {
        var entry = Entry(agent: event.source, session: event.sessionID)
        switch event.name {
        case HookEvent.userPromptSubmit:
            entry.prompt = true
        case HookEvent.preToolUse, HookEvent.postToolUse:
            let native = event.raw["native_event"]?.stringValue
            guard !notTools.contains(native ?? "") else { break }
            let fallback: String?
            switch native {
            case "afterShellExecution", "post_run_command": fallback = "Bash"
            case "afterFileEdit", "post_write_code": fallback = "Edit"
            case "post_read_code": fallback = "Read"
            case "afterMCPExecution", "post_mcp_tool_use": fallback = "MCP"
            default: fallback = nil
            }
            entry.tool = (event.toolName?.isEmpty == false ? event.toolName : fallback).map(toolName)
            entry.callID = (event.raw["tool_use_id"] ?? event.raw["toolUseId"] ?? event.raw["tool_call_id"] ?? event.raw["toolCallId"])?.stringValue
            entry.before = event.name == HookEvent.preToolUse
        default:
            break
        }
        return entry
    }

    /// `mcp__github__create_issue` → `mcp:github.create_issue`.
    public static func toolName(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.hasPrefix("mcp__") else { return String(name.prefix(64)) }
        let parts = name.dropFirst(5).components(separatedBy: "__").filter { !$0.isEmpty }
        guard let server = parts.first else { return "mcp" }
        let rest = parts.dropFirst().joined(separator: ".")
        return String((rest.isEmpty ? "mcp:" + server : "mcp:" + server + "." + rest).prefix(64))
    }

    private func add(_ entry: Entry, at date: Date) {
        guard !entry.agent.isEmpty else { return }
        let day = Self.dayID(date, calendar: calendar)
        if day != seenDay {
            seenDay = day
            seenSessions = loadSeen(day: day)
        }
        let key = day + "|" + entry.agent
        var row = counts[key] ?? (0, 0, 0)
        if !entry.session.isEmpty, seenSessions.insert(key + "|" + entry.session).inserted { row.sessions += 1 }
        if entry.prompt { row.prompts += 1 }
        if let tool = entry.tool, countsCall(entry) {
            row.tools += 1
            toolCounts[key + "|" + tool, default: 0] += 1
        }
        counts[key] = row
    }

    /// One call is counted once, whether the agent reports it before, after, or both.
    private func countsCall(_ entry: Entry) -> Bool {
        let session = entry.agent + "|" + entry.session
        if entry.before { announcing.insert(session) }
        if let id = entry.callID, !id.isEmpty {
            let key = session + "|" + id
            guard seenCalls.insert(key).inserted else { return false }
            callOrder.append(key)
            if callOrder.count > 50_000 {
                let drop = callOrder.prefix(10_000)
                seenCalls.subtract(drop)
                callOrder.removeFirst(10_000)
            }
            return true
        }
        return entry.before || !announcing.contains(session)
    }

    static func dayID(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Storage (on `queue`)

    private func open() -> SQLiteDB? {
        if let db { return db }
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let opened = try SQLiteDB(path: path.path)
            try opened.execute("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS daily (day TEXT NOT NULL, agent TEXT NOT NULL, sessions INTEGER NOT NULL DEFAULT 0,
                    prompts INTEGER NOT NULL DEFAULT 0, tools INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (day, agent));
                CREATE TABLE IF NOT EXISTS tools (day TEXT NOT NULL, agent TEXT NOT NULL, tool TEXT NOT NULL,
                    count INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (day, agent, tool));
                CREATE TABLE IF NOT EXISTS seen (day TEXT NOT NULL, agent TEXT NOT NULL, session TEXT NOT NULL,
                    PRIMARY KEY (day, agent, session));
                """)
            db = opened
            return opened
        } catch {
            // A file that cannot be used is set aside, once; counting goes on in a fresh one.
            if let failure = error as? SQLiteError, failure.isCorruption {
                try? FileManager.default.moveItem(at: path, to: path.appendingPathExtension("broken"))
            }
            return nil
        }
    }

    private func loadSeen(day: String) -> Set<String> {
        guard let db = open(), let rows = try? db.query("SELECT agent, session FROM seen WHERE day = ?", [.text(day)]) else { return [] }
        return Set(rows.compactMap { row in
            guard let agent = row[0].stringValue, let session = row[1].stringValue else { return nil }
            return day + "|" + agent + "|" + session
        })
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + 3) { [self] in
            flushScheduled = false
            write()
        }
    }

    private func write() {
        guard !counts.isEmpty || !toolCounts.isEmpty, let db = open() else { return }
        let rows = counts, tools = toolCounts, sessions = seenSessions
        do {
            try db.transaction {
                for (key, row) in rows {
                    let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { continue }
                    try db.run("""
                        INSERT INTO daily (day, agent, sessions, prompts, tools) VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(day, agent) DO UPDATE SET sessions = sessions + excluded.sessions,
                            prompts = prompts + excluded.prompts, tools = tools + excluded.tools
                        """, [.text(parts[0]), .text(parts[1]), .integer(Int64(row.sessions)), .integer(Int64(row.prompts)), .integer(Int64(row.tools))])
                }
                for (key, count) in tools {
                    let parts = key.split(separator: "|", maxSplits: 2).map(String.init)
                    guard parts.count == 3 else { continue }
                    try db.run("""
                        INSERT INTO tools (day, agent, tool, count) VALUES (?, ?, ?, ?)
                        ON CONFLICT(day, agent, tool) DO UPDATE SET count = count + excluded.count
                        """, [.text(parts[0]), .text(parts[1]), .text(parts[2]), .integer(Int64(count))])
                }
                for key in sessions {
                    let parts = key.split(separator: "|", maxSplits: 2).map(String.init)
                    guard parts.count == 3 else { continue }
                    try db.run("INSERT OR IGNORE INTO seen (day, agent, session) VALUES (?, ?, ?)",
                               [.text(parts[0]), .text(parts[1]), .text(parts[2])])
                }
            }
            counts = [:]
            toolCounts = [:]
            if !pruned { prune(db) }
        } catch {
            // Kept in memory; tried again with the next event.
        }
    }

    private func prune(_ db: SQLiteDB) {
        pruned = true
        let cutoff = Self.dayID(clock().addingTimeInterval(-Double(Self.retentionDays) * 86_400), calendar: calendar)
        for table in ["daily", "tools", "seen"] { try? db.run("DELETE FROM \(table) WHERE day < ?", [.text(cutoff)]) }
        try? db.run("DELETE FROM seen WHERE day < ?", [.text(Self.dayID(clock().addingTimeInterval(-3 * 86_400), calendar: calendar))])
    }

    /// Writes what is waiting now (tests, and before the app quits).
    public func flush() {
        queue.sync { write() }
    }

    // MARK: Reading

    /// The record as the usage view shows it. Runs on the ledger's own queue.
    public func snapshot(now: Date? = nil, completion: @escaping @Sendable (ActivitySnapshot) -> Void) {
        queue.async { [self] in completion(makeSnapshot(now: now ?? clock())) }
    }

    public func snapshotNow(now: Date? = nil) -> ActivitySnapshot {
        queue.sync { makeSnapshot(now: now ?? clock()) }
    }

    private func makeSnapshot(now: Date) -> ActivitySnapshot {
        write()
        var snapshot = ActivitySnapshot()
        guard let db = open() else { return snapshot }
        let dayIDs = (0..<Self.heatmapDays).reversed().map { back in
            Self.dayID(calendar.date(byAdding: .day, value: -back, to: now) ?? now, calendar: calendar)
        }
        guard let first = dayIDs.first, let today = dayIDs.last else { return snapshot }
        let weekStart = dayIDs[max(0, dayIDs.count - 7)]
        let monthStart = dayIDs[max(0, dayIDs.count - 30)]
        do {
            var perAgent: [String: [String: ActivitySnapshot.Day]] = [:]
            for row in try db.query("SELECT day, agent, sessions, prompts, tools FROM daily WHERE day >= ? AND day <= ?", [.text(first), .text(today)]) {
                guard let day = row[0].stringValue, let agent = row[1].stringValue else { continue }
                let entry = ActivitySnapshot.Day(id: day, sessions: row[2].intValue, prompts: row[3].intValue, tools: row[4].intValue)
                perAgent[agent, default: [:]][day] = entry
                var all = perAgent["all", default: [:]][day] ?? ActivitySnapshot.Day(id: day)
                all.sessions += entry.sessions
                all.prompts += entry.prompts
                all.tools += entry.tools
                perAgent["all", default: [:]][day] = all
            }
            for (agent, days) in perAgent {
                snapshot.days[agent] = dayIDs.map { days[$0] ?? ActivitySnapshot.Day(id: $0) }
            }
            var tools: [String: [String: Int]] = [:]
            for row in try db.query("SELECT agent, tool, SUM(count) FROM tools WHERE day >= ? GROUP BY agent, tool", [.text(weekStart)]) {
                guard let agent = row[0].stringValue, let tool = row[1].stringValue else { continue }
                tools[agent, default: [:]][tool, default: 0] += row[2].intValue
                tools["all", default: [:]][tool, default: 0] += row[2].intValue
            }
            for (agent, counts) in tools {
                snapshot.tools[agent] = counts.map { ActivitySnapshot.Tool(name: $0.key, count: $0.value) }
                    .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
                    .prefix(8).map { $0 }
            }
            snapshot.agents = perAgent.keys.filter { $0 != "all" }.map { agent in
                let days = snapshot.days[agent] ?? []
                func sum(from start: String, _ value: (ActivitySnapshot.Day) -> Int) -> Int {
                    days.filter { $0.id >= start }.reduce(0) { $0 + value($1) }
                }
                return ActivitySnapshot.Agent(id: agent, sessions7: sum(from: weekStart, \.sessions), prompts7: sum(from: weekStart, \.prompts),
                                              tools7: sum(from: weekStart, \.tools), sessions30: sum(from: monthStart, \.sessions))
            }
            .filter { $0.sessions30 > 0 }
            .sorted { ($0.sessions7, $0.sessions30, $1.id) > ($1.sessions7, $1.sessions30, $0.id) }
            snapshot.updatedAt = now
        } catch {
            return snapshot
        }
        return snapshot
    }
}

/// Days of activity per agent ("all" for every agent together), newest last.
public struct ActivitySnapshot: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public var id: String
        public var sessions = 0
        public var prompts = 0
        public var tools = 0
        public init(id: String, sessions: Int = 0, prompts: Int = 0, tools: Int = 0) {
            self.id = id
            self.sessions = sessions
            self.prompts = prompts
            self.tools = tools
        }
        /// What the heatmap shades by: things asked and things done.
        public var weight: Int { prompts + tools }
    }

    public struct Tool: Equatable, Sendable, Identifiable {
        public var name: String
        public var count: Int
        public var id: String { name }
        public init(name: String, count: Int) {
            self.name = name
            self.count = count
        }
    }

    public struct Agent: Equatable, Sendable, Identifiable {
        public var id: String
        public var sessions7: Int
        public var prompts7: Int
        public var tools7: Int
        public var sessions30: Int
        public init(id: String, sessions7: Int, prompts7: Int, tools7: Int, sessions30: Int) {
            self.id = id
            self.sessions7 = sessions7
            self.prompts7 = prompts7
            self.tools7 = tools7
            self.sessions30 = sessions30
        }
    }

    /// `ActivityLedger.heatmapDays` days per agent, oldest first.
    public var days: [String: [Day]] = [:]
    /// The most used tools of the last seven days, per agent.
    public var tools: [String: [Tool]] = [:]
    /// Agents with a session in the last 30 days, busiest this week first.
    public var agents: [Agent] = []
    public var updatedAt: Date?

    public init() {}

    public var isEmpty: Bool { agents.isEmpty }

    /// Days in a row, up to today, with something done (today may still be empty).
    public func streak(_ agent: String) -> Int {
        let days = self.days[agent] ?? []
        var count = 0
        for (index, day) in days.reversed().enumerated() {
            if day.weight > 0 || day.sessions > 0 { count += 1 } else if index > 0 { break }
        }
        return count
    }

    /// The last `count` days of an agent added up.
    public func total(_ agent: String, lastDays count: Int) -> Day {
        (days[agent] ?? []).suffix(count).reduce(into: Day(id: "")) { total, day in
            total.sessions += day.sessions
            total.prompts += day.prompts
            total.tools += day.tools
        }
    }

    /// Made-up numbers for documentation images.
    public static func demo(now: Date) -> ActivitySnapshot {
        var snapshot = ActivitySnapshot()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var generator = SeededGenerator(seed: 7)
        func series(scale: Double) -> [Day] {
            (0..<ActivityLedger.heatmapDays).reversed().map { back in
                let date = calendar.date(byAdding: .day, value: -back, to: now) ?? now
                let weekday = calendar.component(.weekday, from: date)
                let weekend = weekday == 1 || weekday == 7
                // Quieter long ago, busier lately, light at weekends, the odd day off.
                let ramp = 0.35 + 0.65 * Double(ActivityLedger.heatmapDays - back) / Double(ActivityLedger.heatmapDays)
                let off = Double(generator.next() % 100) < (weekend ? 55 : 8)
                let base = off ? 0 : (weekend ? 0.3 : 1) * ramp * scale * (0.4 + Double(generator.next() % 100) / 100)
                return Day(id: ActivityLedger.dayID(date, calendar: calendar), sessions: Int(base * 6),
                           prompts: Int(base * 24), tools: Int(base * 140))
            }
        }
        let claude = series(scale: 1), codex = series(scale: 0.45), cursor = series(scale: 0.25)
        snapshot.days = ["claude": claude, "codex": codex, "cursor": cursor]
        snapshot.days["all"] = claude.indices.map { index in
            Day(id: claude[index].id, sessions: claude[index].sessions + codex[index].sessions + cursor[index].sessions,
                prompts: claude[index].prompts + codex[index].prompts + cursor[index].prompts,
                tools: claude[index].tools + codex[index].tools + cursor[index].tools)
        }
        snapshot.tools = [
            "all": [Tool(name: "Bash", count: 812), Tool(name: "Read", count: 640), Tool(name: "Edit", count: 402),
                    Tool(name: "Grep", count: 233), Tool(name: "mcp:github.create_pr", count: 41), Tool(name: "WebFetch", count: 18)],
            "claude": [Tool(name: "Bash", count: 520), Tool(name: "Read", count: 488), Tool(name: "Edit", count: 301), Tool(name: "Grep", count: 190)],
            "codex": [Tool(name: "Bash", count: 292), Tool(name: "Edit", count: 101)],
            "cursor": [Tool(name: "Edit", count: 64), Tool(name: "Bash", count: 30)],
        ]
        snapshot.agents = ["claude", "codex", "cursor"].map { id in
            let week = (snapshot.days[id] ?? []).suffix(7)
            return Agent(id: id, sessions7: week.reduce(0) { $0 + $1.sessions }, prompts7: week.reduce(0) { $0 + $1.prompts },
                         tools7: week.reduce(0) { $0 + $1.tools }, sessions30: (snapshot.days[id] ?? []).suffix(30).reduce(0) { $0 + $1.sessions })
        }
        snapshot.updatedAt = now
        return snapshot
    }
}

/// A small deterministic generator, so documentation images do not change from run to run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
