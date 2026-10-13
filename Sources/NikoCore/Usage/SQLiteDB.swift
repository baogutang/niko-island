import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible, Equatable {
    public let code: Int32
    public let message: String
    public var description: String { "sqlite error \(code): \(message)" }

    /// The file itself is unusable (as opposed to a bad statement or a busy lock).
    public var isCorruption: Bool {
        let primary = code & 0xFF
        return primary == SQLITE_CORRUPT || primary == SQLITE_NOTADB
    }
}

/// Minimal wrapper over the system SQLite: one connection, used from one queue.
public final class SQLiteDB {
    public enum Value: Equatable, Sendable {
        case integer(Int64)
        case real(Double)
        case text(String)
        case null

        public var intValue: Int { if case .integer(let v) = self { return Int(v) } else { return 0 } }
        public var doubleValue: Double {
            switch self {
            case .real(let v): return v
            case .integer(let v): return Double(v)
            default: return 0
            }
        }
        public var stringValue: String? { if case .text(let v) = self { return v } else { return nil } }
    }

    private var handle: OpaquePointer?
    public let path: String
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// `readOnly` opens someone else's database: nothing is created, nothing is written.
    public init(path: String, readOnly: Bool = false) throws {
        self.path = path
        var db: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(path, &db, flags, nil)
        guard code == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            if let db { sqlite3_close_v2(db) }
            throw SQLiteError(code: code, message: message)
        }
        handle = db
        sqlite3_busy_timeout(db, 3000)
    }

    deinit { close() }

    public func close() {
        if let handle { sqlite3_close_v2(handle) }
        handle = nil
    }

    private func failure(_ code: Int32) -> SQLiteError {
        SQLiteError(code: sqlite3_extended_errcode(handle), message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "closed")
    }

    public func execute(_ sql: String) throws {
        guard let handle else { throw SQLiteError(code: SQLITE_MISUSE, message: "closed") }
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw failure(code) }
    }

    private func prepare(_ sql: String, _ parameters: [Value]) throws -> OpaquePointer {
        guard let handle else { throw SQLiteError(code: SQLITE_MISUSE, message: "closed") }
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else { throw failure(code) }
        for (index, value) in parameters.enumerated() {
            let position = Int32(index + 1)
            let bound: Int32
            switch value {
            case .integer(let v): bound = sqlite3_bind_int64(statement, position, v)
            case .real(let v): bound = sqlite3_bind_double(statement, position, v)
            case .text(let v): bound = sqlite3_bind_text(statement, position, v, -1, SQLiteDB.transient)
            case .null: bound = sqlite3_bind_null(statement, position)
            }
            guard bound == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw failure(bound)
            }
        }
        return statement
    }

    /// Runs a statement that returns no rows.
    public func run(_ sql: String, _ parameters: [Value] = []) throws {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE || code == SQLITE_ROW else { throw failure(code) }
    }

    public func query(_ sql: String, _ parameters: [Value] = []) throws -> [[Value]] {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        var rows: [[Value]] = []
        let columns = sqlite3_column_count(statement)
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw failure(code) }
            var row: [Value] = []
            row.reserveCapacity(Int(columns))
            for column in 0..<columns {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row.append(.integer(sqlite3_column_int64(statement, column)))
                case SQLITE_FLOAT: row.append(.real(sqlite3_column_double(statement, column)))
                case SQLITE_TEXT: row.append(.text(String(cString: sqlite3_column_text(statement, column))))
                default: row.append(.null)
                }
            }
            rows.append(row)
        }
        return rows
    }

    public func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}
