import Foundation
import SQLite3

enum DatabaseError: Error, Equatable {
    case sqlite(code: Int32, message: String)
    case unexpectedNull(column: String)
}

/// Serializes all SQLite access on a private queue so `Database` can be `Sendable`
/// without exposing the underlying connection across threads unsynchronized.
final class Database: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.piboard.database")
    private let connection: Connection

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let handle {
                sqlite3_close_v2(handle)
            }
            throw DatabaseError.sqlite(code: rc, message: message)
        }
        connection = Connection(handle: handle)

        try connection.execute(sql: "PRAGMA foreign_keys = ON;")
        if path != ":memory:" {
            try connection.execute(sql: "PRAGMA journal_mode = WAL;")
        }
        try connection.execute(sql: "PRAGMA busy_timeout = 5000;")
    }

    deinit {
        sqlite3_close_v2(connection.handle)
    }

    func perform<T>(_ work: (Connection) throws -> T) rethrows -> T {
        try queue.sync {
            try work(connection)
        }
    }
}

/// Thin wrapper around a raw `sqlite3*` handle; all methods assume they run on
/// `Database`'s serial queue.
final class Connection {
    fileprivate let handle: OpaquePointer

    fileprivate init(handle: OpaquePointer) {
        self.handle = handle
    }

    func execute(sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        if rc != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? lastErrorMessage()
            sqlite3_free(errorPointer)
            throw DatabaseError.sqlite(code: rc, message: message)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw DatabaseError.sqlite(code: rc, message: lastErrorMessage())
        }
        return Statement(handle: stmt, connection: self)
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute(sql: "BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try execute(sql: "COMMIT;")
            return result
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }
    }

    var userVersion: Int {
        get {
            guard let statement = try? prepare("PRAGMA user_version;"),
                  (try? statement.step()) == true else {
                return 0
            }
            return Int(statement.columnInt(at: 0))
        }
        set {
            try? execute(sql: "PRAGMA user_version = \(newValue);")
        }
    }

    fileprivate func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(handle))
    }
}

final class Statement {
    private let handle: OpaquePointer
    private unowned let connection: Connection

    fileprivate init(handle: OpaquePointer, connection: Connection) {
        self.handle = handle
        self.connection = connection
    }

    deinit {
        sqlite3_finalize(handle)
    }

    @discardableResult
    func step() throws -> Bool {
        let rc = sqlite3_step(handle)
        switch rc {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw DatabaseError.sqlite(code: rc, message: connection.lastErrorMessage())
        }
    }

    func bind(_ value: String, at index: Int32) {
        sqlite3_bind_text(handle, index, value, -1, SQLITE_TRANSIENT)
    }

    func bind(_ value: String?, at index: Int32) {
        if let value {
            sqlite3_bind_text(handle, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(handle, index)
        }
    }

    func bind(_ value: Int, at index: Int32) {
        sqlite3_bind_int64(handle, index, Int64(value))
    }

    func column(_ name: String, at index: Int32) throws -> String {
        guard let cString = sqlite3_column_text(handle, index) else {
            throw DatabaseError.unexpectedNull(column: name)
        }
        return String(cString: cString)
    }

    func columnOptionalString(at index: Int32) -> String? {
        guard sqlite3_column_type(handle, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(handle, index) else {
            return nil
        }
        return String(cString: cString)
    }

    func columnInt(at index: Int32) -> Int {
        Int(sqlite3_column_int64(handle, index))
    }
}

// SQLite needs an explicit destructor constant when binding transient (copied) text.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
