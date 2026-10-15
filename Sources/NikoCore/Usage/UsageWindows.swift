import Foundation

// Per-agent windows, the provider limits found on disk, and usage that lives
// in another app's database rather than in a transcript.

extension UsageStore {
    /// Totals per agent and model for everything at or after `timestamp` (unix seconds).
    public func totals(since timestamp: Double) throws -> [UsageTotals] {
        let rows = try db.query("""
            SELECT agent, model, SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens), SUM(cache_write_tokens),
                   SUM(reasoning_tokens), SUM(estimated_cost), COUNT(*)
            FROM events WHERE ts >= ?
            GROUP BY agent, model ORDER BY SUM(estimated_cost) DESC, SUM(output_tokens) DESC, agent, model
            """, [.real(timestamp)])
        return rows.map {
            UsageTotals(agent: $0[0].stringValue ?? "", model: $0[1].stringValue ?? "", input: $0[2].intValue,
                        output: $0[3].intValue, cacheRead: $0[4].intValue, cacheWrite: $0[5].intValue,
                        reasoning: $0[6].intValue, cost: $0[7].doubleValue, messages: $0[8].intValue)
        }
    }

    /// Tokens per agent in stretches of `seconds` (counted from 1970), since `timestamp`:
    /// stretch → agent → tokens.
    public func stretches(since timestamp: Double, seconds: Int) throws -> [Int: [String: Int]] {
        let rows = try db.query("""
            SELECT CAST(ts / ? AS INTEGER), agent, SUM(input_tokens + output_tokens + cache_read_tokens + cache_write_tokens)
            FROM events WHERE ts >= ? GROUP BY 1, 2
            """, [.integer(Int64(seconds)), .real(timestamp)])
        var out: [Int: [String: Int]] = [:]
        for row in rows { out[row[0].intValue, default: [:]][row[1].stringValue ?? ""] = row[2].intValue }
        return out
    }

    /// Tokens and cost per agent and day.
    public func dailyTotalsByAgent(fromDay: String, toDay: String) throws -> [String: [String: (tokens: Int, cost: Double)]] {
        let rows = try db.query("""
            SELECT agent, day, SUM(input_tokens + output_tokens + cache_read_tokens + cache_write_tokens), SUM(estimated_cost)
            FROM events WHERE day >= ? AND day <= ? GROUP BY agent, day
            """, [.text(fromDay), .text(toDay)])
        var out: [String: [String: (tokens: Int, cost: Double)]] = [:]
        for row in rows {
            out[row[0].stringValue ?? "", default: [:]][row[1].stringValue ?? ""] = (row[2].intValue, row[3].doubleValue)
        }
        return out
    }

    /// Tokens and cost per agent and month ("YYYY-MM") from a day on.
    public func monthlyTotalsByAgent(fromDay: String) throws -> [String: [String: (tokens: Int, cost: Double)]] {
        let rows = try db.query("""
            SELECT agent, substr(day, 1, 7), SUM(input_tokens + output_tokens + cache_read_tokens + cache_write_tokens), SUM(estimated_cost)
            FROM events WHERE day >= ? GROUP BY 1, 2
            """, [.text(fromDay)])
        var out: [String: [String: (tokens: Int, cost: Double)]] = [:]
        for row in rows {
            out[row[0].stringValue ?? "", default: [:]][row[1].stringValue ?? ""] = (row[2].intValue, row[3].doubleValue)
        }
        return out
    }

    /// Tokens and estimated cost per session since `timestamp`, keyed "agent/session id".
    public func sessionTotals(since timestamp: Double, limit: Int = 300) throws -> [String: UsageSnapshot.SessionUse] {
        let rows = try db.query("""
            SELECT agent, session, SUM(input_tokens + output_tokens + cache_read_tokens + cache_write_tokens), SUM(estimated_cost), MAX(ts)
            FROM events WHERE ts >= ? AND session IS NOT NULL AND session != ''
            GROUP BY agent, session ORDER BY MAX(ts) DESC LIMIT ?
            """, [.real(timestamp), .integer(Int64(limit))])
        var out: [String: UsageSnapshot.SessionUse] = [:]
        for row in rows {
            guard let agent = row[0].stringValue, let session = row[1].stringValue else { continue }
            out[agent + "/" + session] = UsageSnapshot.SessionUse(tokens: row[2].intValue, cost: row[3].doubleValue)
        }
        return out
    }

    /// Small things worth remembering between runs (a cursor, the last limits seen).
    public func meta(_ key: String) throws -> String? {
        try db.query("SELECT value FROM meta WHERE key = ?", [.text(key)]).first?.first?.stringValue
    }

    public func setMeta(_ key: String, _ value: String?) throws {
        if let value {
            try db.run("INSERT INTO meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       [.text(key), .text(value)])
        } else {
            try db.run("DELETE FROM meta WHERE key = ?", [.text(key)])
        }
    }
}

/// Where a set of limits was learned.
public enum LimitsSource: String, Sendable, Equatable {
    /// Something the agent wrote to disk for its own purposes (Codex rollouts).
    case agentFiles = "files"
    /// Claude Code's status line.
    case statusLine = "statusline"
    /// What the agent last fetched for itself and kept on disk; as old as that.
    case agentCache = "cache"
    /// The provider, asked directly (opt-in).
    case provider
    /// The agent was turned away: all that is known is that the window is full, and until when.
    case limitReached = "reached"
}

/// Limits a provider reports about itself.
public struct ProviderLimits: Sendable, Equatable {
    public var windows: [RateLimitWindow] = []
    public var capturedAt: Date?
    public var plan: String?
    public var source: LimitsSource?
    /// Quota resets the account may still spend, where the provider says.
    public var resetsLeft: Int?

    public init(windows: [RateLimitWindow] = [], capturedAt: Date? = nil, plan: String? = nil, source: LimitsSource? = nil) {
        self.windows = windows
        self.capturedAt = capturedAt
        self.plan = plan
        self.source = source
    }

    /// Windows that have reset since they were captured no longer say anything true.
    public func current(now: Date) -> ProviderLimits {
        var copy = self
        copy.windows = windows.filter { $0.resetsAt.map { $0 > now } ?? true }
        return copy
    }

    /// Several sources may know the same window; the one that looked last is right.
    public static func merged(_ candidates: [ProviderLimits], now: Date) -> ProviderLimits? {
        let live = candidates.map { $0.current(now: now) }.filter { !$0.windows.isEmpty }
            .sorted { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
        guard var out = live.first else { return nil }
        for other in live.dropFirst() {
            for window in other.windows where !out.windows.contains(where: { $0.id == window.id }) { out.windows.append(window) }
            out.plan = out.plan ?? other.plan
            out.resetsLeft = out.resetsLeft ?? other.resetsLeft
        }
        return out
    }

    var json: String {
        var object = JSONObject()
        if let capturedAt { object["captured_at"] = .number(String(capturedAt.timeIntervalSince1970)) }
        if let plan { object["plan"] = .string(plan) }
        if let source { object["source"] = .string(source.rawValue) }
        if let resetsLeft { object["resets_left"] = .int(resetsLeft) }
        object["windows"] = .array(windows.map { window in
            var item = JSONObject(["id": .string(window.id), "used": .number(String(window.usedPercent))])
            if let resets = window.resetsAt { item["resets_at"] = .number(String(resets.timeIntervalSince1970)) }
            if let minutes = window.windowMinutes { item["minutes"] = .int(minutes) }
            return .object(item)
        })
        return JSONValue.object(object).serialized(.compact)
    }

    init?(json: String) {
        guard let root = try? JSONValue.parse(json), root.objectValue != nil else { return nil }
        capturedAt = ISOTime.date(root["captured_at"]?.doubleValue)
        plan = root["plan"]?.stringValue
        source = root["source"]?.stringValue.flatMap(LimitsSource.init(rawValue:))
        resetsLeft = root["resets_left"]?.intValue
        windows = (root["windows"]?.arrayValue ?? []).compactMap { item in
            guard let id = item["id"]?.stringValue, let used = item["used"]?.doubleValue else { return nil }
            return RateLimitWindow(id: id, usedPercent: used,
                                   resetsAt: ISOTime.date(item["resets_at"]?.doubleValue),
                                   windowMinutes: item["minutes"]?.intValue)
        }
    }
}

/// Codex writes its limits next to every token count in a rollout:
/// `payload.rate_limits.{primary,secondary}.{used_percent, window_minutes, resets_at}`.
public enum CodexLimits {
    /// The most recent limits in the tail of a rollout file.
    public static func latest(inTail tail: Data) -> ProviderLimits? {
        let needle = Data("\"rate_limits\"".utf8)
        for line in tail.split(separator: 0x0A, omittingEmptySubsequences: true).reversed() {
            guard line.range(of: needle) != nil,
                  let object = (try? JSONValue.parse(Data(line), skipping: ["info"]))?.objectValue,
                  let limits = object["payload"]?["rate_limits"], limits.objectValue != nil else { continue }
            var out = ProviderLimits(source: .agentFiles)
            out.capturedAt = ISOTime.flexible(object["timestamp"]).map(Date.init(timeIntervalSince1970:))
            out.plan = limits["plan_type"]?.stringValue
            for key in ["primary", "secondary"] {
                guard let window = limits[key], window.objectValue != nil,
                      let used = window["used_percent"]?.doubleValue, used.isFinite else { continue }
                out.windows.append(RateLimitWindow(
                    id: key, usedPercent: min(max(used, 0), 100),
                    resetsAt: ISOTime.flexible(window["resets_at"]).map(Date.init(timeIntervalSince1970:)),
                    windowMinutes: window["window_minutes"]?.intValue))
            }
            return out
        }
        return nil
    }

    public static func latest(inFile path: String, tailBytes: Int = 256 * 1024) -> ProviderLimits? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        return latest(inTail: (try? handle.readToEnd()) ?? Data())
    }
}

/// ZCode keeps one row per model request in its own SQLite database
/// (`~/.zcode/cli/db/db.sqlite`, table `model_usage`). It is opened read-only
/// and only the numbers are read.
public enum ZCodeUsage {
    public static let agent = "zcode"
    static let cursorKey = "zcode.model_usage.rowid"

    public static func databasePath(home: URL) -> String { home.appendingPathComponent(".zcode/cli/db/db.sqlite").path }

    /// Rows newer than `cursor`, as usage records, and the cursor to continue from.
    static func read(path: String, after cursor: Int64, limit: Int = 4000) throws -> (records: [UsageRecord], cursor: Int64) {
        let db = try SQLiteDB(path: path, readOnly: true)
        defer { db.close() }
        let rows = try db.query("""
            SELECT rowid, id, session_id, model_id, completed_at, input_tokens, output_tokens, reasoning_tokens,
                   cache_creation_input_tokens, cache_read_input_tokens
            FROM model_usage WHERE rowid > ? AND completed_at IS NOT NULL ORDER BY rowid LIMIT ?
            """, [.integer(cursor), .integer(Int64(limit))])
        var records: [UsageRecord] = []
        var last = cursor
        for row in rows {
            guard case .integer(let rowid) = row[0] else { continue }
            last = max(last, rowid)
            let cacheRead = row[9].intValue
            let cacheWrite = row[8].intValue
            // ZCode's input count includes what came from the cache.
            let input = max(0, row[5].intValue - cacheRead - cacheWrite)
            let output = row[6].intValue
            guard input + output + cacheRead + cacheWrite > 0 else { continue }
            let completed = row[4].doubleValue
            records.append(UsageRecord(
                identityKey: UsageRecord.identity(agent, row[1].stringValue ?? String(rowid)),
                timestamp: completed > 100_000_000_000 ? completed / 1000 : completed,
                agent: agent, model: row[3].stringValue ?? "unknown", session: row[2].stringValue, project: nil,
                input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite, reasoning: row[7].intValue))
        }
        return (records, last)
    }

    /// Copies whatever is new into our store. Returns how many records were added.
    @discardableResult
    static func sync(home: URL, store: UsageStore, pricing: Pricing) throws -> Int {
        let path = databasePath(home: home)
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        var cursor = Int64((try store.meta(cursorKey)) ?? "") ?? 0
        var added = 0
        while true {
            let batch = try read(path: path, after: cursor)
            guard batch.cursor > cursor else { break }
            try store.commit(records: batch.records, pricing: pricing, file: nil)
            try store.setMeta(cursorKey, String(batch.cursor))
            cursor = batch.cursor
            added += batch.records.count
            if batch.records.count < 100 { break }
        }
        return added
    }
}
