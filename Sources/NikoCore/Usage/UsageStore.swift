import CryptoKit
import Foundation

/// One usage data point extracted from a transcript. Numbers and identifiers
/// only — never message text.
public struct UsageRecord: Sendable, Equatable {
    public var identityKey: String
    public var kind = "message"
    /// Unix seconds.
    public var timestamp: Double
    public var agent: String
    public var model: String
    public var session: String?
    public var project: String?
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var cacheWrite = 0
    public var reasoning = 0
    /// Cost stated by the transcript itself, when there is one.
    public var reportedCost: Double?

    public var totalTokens: Int { input + output + cacheRead + cacheWrite }

    /// PROTOCOLS §6.1: `identity_key = hash(provider, …ids)`.
    public static func identity(_ parts: String...) -> String {
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

public struct SourceFileState: Sendable, Equatable {
    public var path: String
    public var provider: String
    public var fileIdentity: String
    public var generation: Int
    public var size: Int
    public var mtime: Double
    public var committedOffset: Int
    public var tailHash: String
    public var parserVersion: Int
    public var status: String
}

public struct UsageTotals: Sendable, Equatable {
    public var agent: String
    public var model: String
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var cacheWrite = 0
    public var reasoning = 0
    public var cost = 0.0
    public var messages = 0

    public var tokens: Int { input + output + cacheRead + cacheWrite }
}

/// SQLite (WAL) storage for usage, schema per PROTOCOLS §6.1.
/// The database is a cache of what the transcripts say: if it is ever
/// unreadable it is set aside and rebuilt from the transcripts.
public final class UsageStore {
    public static let schema = """
    CREATE TABLE IF NOT EXISTS source_files(
      id INTEGER PRIMARY KEY, path TEXT NOT NULL, provider TEXT NOT NULL,
      file_identity TEXT NOT NULL, generation INTEGER NOT NULL,
      size INTEGER NOT NULL, mtime REAL NOT NULL,
      committed_offset INTEGER NOT NULL, tail_hash TEXT NOT NULL,
      parser_version INTEGER NOT NULL, status TEXT NOT NULL,
      UNIQUE(path, generation));
    CREATE TABLE IF NOT EXISTS events(
      id INTEGER PRIMARY KEY, identity_key TEXT NOT NULL UNIQUE,
      event_kind TEXT NOT NULL, ts REAL NOT NULL, day TEXT NOT NULL,
      agent TEXT NOT NULL, model TEXT NOT NULL, session TEXT, project TEXT,
      input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL,
      cache_read_tokens INTEGER NOT NULL, cache_write_tokens INTEGER NOT NULL,
      reasoning_tokens INTEGER NOT NULL,
      estimated_cost REAL NOT NULL, cost_source TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS events_day ON events(day);
    """

    private var db: SQLiteDB
    public let path: String
    public let timeZone: TimeZone
    /// Set when the previous database had to be set aside on open.
    public private(set) var recoveredFromCorruption = false

    public init(path: String, timeZone: TimeZone = .current) throws {
        self.path = path
        self.timeZone = timeZone
        do {
            db = try UsageStore.open(path)
        } catch let error as SQLiteError where error.isCorruption {
            UsageStore.setAside(path)
            db = try UsageStore.open(path)
            recoveredFromCorruption = true
        }
    }

    private static func open(_ path: String) throws -> SQLiteDB {
        let db = try SQLiteDB(path: path)
        do {
            try db.execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
            try db.execute(schema)
            // Touch both tables so a damaged file is noticed now rather than mid-sync.
            _ = try db.query("SELECT count(*) FROM events")
            _ = try db.query("SELECT count(*) FROM source_files")
            let check = try db.query("PRAGMA quick_check(1)")
            if check.first?.first?.stringValue != "ok" {
                throw SQLiteError(code: 11, message: "quick_check: \(check.first?.first?.stringValue ?? "?")")
            }
        } catch {
            db.close()
            throw error
        }
        chmod(path, 0o600)
        return db
    }

    /// Moves a broken database (and its WAL/SHM) out of the way.
    static func setAside(_ path: String) {
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let source = path + suffix
            guard FileManager.default.fileExists(atPath: source) else { continue }
            if suffix.isEmpty {
                _ = rename(source, "\(path).corrupt-\(stamp)")
            } else {
                unlink(source)
            }
        }
    }

    public func close() { db.close() }

    public func day(for timestamp: Double) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: timestamp))
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Writing

    /// Inserts records, keeping the most complete numbers for an identity that
    /// is seen again (streamed messages are logged several times as they grow).
    public func commit(records: [UsageRecord], pricing: Pricing, file: SourceFileState?) throws {
        try db.transaction {
            for record in records {
                let cost: Double
                let source: String
                if let reported = record.reportedCost {
                    cost = reported
                    source = "reported"
                } else {
                    cost = pricing.cost(of: record) ?? 0
                    source = "estimated"
                }
                try db.run("""
                    INSERT INTO events(identity_key, event_kind, ts, day, agent, model, session, project,
                      input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, reasoning_tokens,
                      estimated_cost, cost_source)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(identity_key) DO UPDATE SET
                      model=excluded.model, input_tokens=excluded.input_tokens, output_tokens=excluded.output_tokens,
                      cache_read_tokens=excluded.cache_read_tokens, cache_write_tokens=excluded.cache_write_tokens,
                      reasoning_tokens=excluded.reasoning_tokens, estimated_cost=excluded.estimated_cost,
                      cost_source=excluded.cost_source
                    WHERE excluded.output_tokens > events.output_tokens
                       OR (excluded.output_tokens = events.output_tokens
                           AND excluded.input_tokens + excluded.cache_read_tokens + excluded.cache_write_tokens
                             > events.input_tokens + events.cache_read_tokens + events.cache_write_tokens)
                    """, [
                        .text(record.identityKey), .text(record.kind), .real(record.timestamp), .text(day(for: record.timestamp)),
                        .text(record.agent), .text(record.model),
                        record.session.map(SQLiteDB.Value.text) ?? .null, record.project.map(SQLiteDB.Value.text) ?? .null,
                        .integer(Int64(record.input)), .integer(Int64(record.output)), .integer(Int64(record.cacheRead)),
                        .integer(Int64(record.cacheWrite)), .integer(Int64(record.reasoning)), .real(cost), .text(source),
                    ])
            }
            if let file { try save(file) }
        }
    }

    private func save(_ file: SourceFileState) throws {
        try db.run("""
            INSERT INTO source_files(path, provider, file_identity, generation, size, mtime, committed_offset, tail_hash, parser_version, status)
            VALUES(?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(path, generation) DO UPDATE SET
              provider=excluded.provider, file_identity=excluded.file_identity, size=excluded.size, mtime=excluded.mtime,
              committed_offset=excluded.committed_offset, tail_hash=excluded.tail_hash,
              parser_version=excluded.parser_version, status=excluded.status
            """, [
                .text(file.path), .text(file.provider), .text(file.fileIdentity), .integer(Int64(file.generation)),
                .integer(Int64(file.size)), .real(file.mtime), .integer(Int64(file.committedOffset)), .text(file.tailHash),
                .integer(Int64(file.parserVersion)), .text(file.status),
            ])
    }

    public func setStatus(_ status: String, path: String, generation: Int) throws {
        try db.run("UPDATE source_files SET status=? WHERE path=? AND generation=?",
                   [.text(status), .text(path), .integer(Int64(generation))])
    }

    // MARK: Reading

    /// The newest generation recorded for a path.
    public func latestState(for path: String) throws -> SourceFileState? {
        let rows = try db.query("""
            SELECT path, provider, file_identity, generation, size, mtime, committed_offset, tail_hash, parser_version, status
            FROM source_files WHERE path=? ORDER BY generation DESC LIMIT 1
            """, [.text(path)])
        return rows.first.map(UsageStore.state)
    }

    public func allLatestStates() throws -> [String: SourceFileState] {
        let rows = try db.query("""
            SELECT s.path, s.provider, s.file_identity, s.generation, s.size, s.mtime, s.committed_offset, s.tail_hash, s.parser_version, s.status
            FROM source_files s JOIN (SELECT path, MAX(generation) AS g FROM source_files GROUP BY path) m
              ON s.path = m.path AND s.generation = m.g
            """)
        var out: [String: SourceFileState] = [:]
        for row in rows {
            let state = UsageStore.state(row)
            out[state.path] = state
        }
        return out
    }

    private static func state(_ row: [SQLiteDB.Value]) -> SourceFileState {
        SourceFileState(path: row[0].stringValue ?? "", provider: row[1].stringValue ?? "", fileIdentity: row[2].stringValue ?? "",
                        generation: row[3].intValue, size: row[4].intValue, mtime: row[5].doubleValue,
                        committedOffset: row[6].intValue, tailHash: row[7].stringValue ?? "",
                        parserVersion: row[8].intValue, status: row[9].stringValue ?? "")
    }

    public func eventCount() throws -> Int {
        try db.query("SELECT count(*) FROM events").first?.first?.intValue ?? 0
    }

    /// Totals per agent and model for `fromDay...toDay` (inclusive, `YYYY-MM-DD`).
    public func totals(fromDay: String, toDay: String) throws -> [UsageTotals] {
        let rows = try db.query("""
            SELECT agent, model, SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens), SUM(cache_write_tokens),
                   SUM(reasoning_tokens), SUM(estimated_cost), COUNT(*)
            FROM events WHERE day >= ? AND day <= ?
            GROUP BY agent, model ORDER BY SUM(estimated_cost) DESC, SUM(output_tokens) DESC, agent, model
            """, [.text(fromDay), .text(toDay)])
        return rows.map {
            UsageTotals(agent: $0[0].stringValue ?? "", model: $0[1].stringValue ?? "", input: $0[2].intValue,
                        output: $0[3].intValue, cacheRead: $0[4].intValue, cacheWrite: $0[5].intValue,
                        reasoning: $0[6].intValue, cost: $0[7].doubleValue, messages: $0[8].intValue)
        }
    }

    public func dailyTotals(fromDay: String, toDay: String) throws -> [String: (tokens: Int, cost: Double)] {
        let rows = try db.query("""
            SELECT day, SUM(input_tokens + output_tokens + cache_read_tokens + cache_write_tokens), SUM(estimated_cost)
            FROM events WHERE day >= ? AND day <= ? GROUP BY day
            """, [.text(fromDay), .text(toDay)])
        var out: [String: (tokens: Int, cost: Double)] = [:]
        for row in rows { out[row[0].stringValue ?? ""] = (row[1].intValue, row[2].doubleValue) }
        return out
    }

    /// Models that have usage but no known price (their cost is counted as 0).
    public func unpricedModels(fromDay: String, toDay: String) throws -> [String] {
        try db.query("""
            SELECT DISTINCT model FROM events
            WHERE day >= ? AND day <= ? AND cost_source='estimated' AND estimated_cost = 0
              AND input_tokens + output_tokens + cache_read_tokens + cache_write_tokens > 0
            ORDER BY model
            """, [.text(fromDay), .text(toDay)]).compactMap { $0[0].stringValue }
    }

    /// Re-prices estimated rows after the price table changed.
    public func reprice(with pricing: Pricing) throws {
        let rows = try db.query("""
            SELECT id, model, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens FROM events WHERE cost_source='estimated'
            """)
        try db.transaction {
            for row in rows {
                let record = UsageRecord(identityKey: "", timestamp: 0, agent: "", model: row[1].stringValue ?? "",
                                         input: row[2].intValue, output: row[3].intValue,
                                         cacheRead: row[4].intValue, cacheWrite: row[5].intValue)
                try db.run("UPDATE events SET estimated_cost=? WHERE id=?",
                           [.real(pricing.cost(of: record) ?? 0), .integer(Int64(row[0].intValue))])
            }
        }
    }
}
