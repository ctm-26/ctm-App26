import Foundation
import SQLite3

let SQLITE_TRANSIENT_BRIDGE = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin Swift wrapper over a single SQLite handle.
/// All public mutating ops are async via the `LedgerDatabase` actor.
public actor LedgerDatabase {
    public let path: String
    private var db: OpaquePointer?

    public init(path: String) throws {
        self.path = path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let h = handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let h = handle { sqlite3_close_v2(h) }
            throw TreasuryError.sqlite(msg)
        }
        self.db = h
        // Pragmas before migration.
        _ = sqlite3_exec(h, "PRAGMA foreign_keys = ON;", nil, nil, nil)
        _ = sqlite3_exec(h, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        // Apply schema.
        for sql in Schema.migrations {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(h, sql, nil, nil, &err) != SQLITE_OK {
                let m = err.map { String(cString: $0) } ?? "unknown sql error"
                sqlite3_free(err)
                sqlite3_close_v2(h)
                throw TreasuryError.sqlite(m)
            }
        }
    }

    deinit {
        if let h = db { sqlite3_close_v2(h) }
    }

    // MARK: - Low-level helpers

    func handle() throws -> OpaquePointer {
        guard let h = db else { throw TreasuryError.sqlite("database is closed") }
        return h
    }

    /// Execute a parameterless statement (or several semicolon-separated).
    public func exec(_ sql: String) throws {
        let h = try handle()
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(h, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(err)
            throw TreasuryError.sqlite(msg)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        let h = try handle()
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(h, sql, -1, &stmt, nil) != SQLITE_OK {
            throw TreasuryError.sqlite(String(cString: sqlite3_errmsg(h)))
        }
        guard let s = stmt else { throw TreasuryError.sqlite("prepare returned nil") }
        return s
    }

    nonisolated public func bindText(_ stmt: OpaquePointer, _ idx: Int32, _ s: String?) {
        if let s = s {
            sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT_BRIDGE)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    nonisolated public func bindInt(_ stmt: OpaquePointer, _ idx: Int32, _ v: Int64?) {
        if let v = v { sqlite3_bind_int64(stmt, idx, v) }
        else { sqlite3_bind_null(stmt, idx) }
    }

    nonisolated public func bindDouble(_ stmt: OpaquePointer, _ idx: Int32, _ v: Double?) {
        if let v = v { sqlite3_bind_double(stmt, idx, v) }
        else { sqlite3_bind_null(stmt, idx) }
    }

    nonisolated public func textColumn(_ stmt: OpaquePointer, _ idx: Int32) -> String? {
        guard let p = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: p)
    }

    /// Run a write inside a transaction. The block performs writes via direct
    /// SQLite calls; this guarantees BEGIN/COMMIT around them.
    public func writeTransaction<T>(_ block: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE;")
        do {
            let result = try block()
            try exec("COMMIT;")
            return result
        } catch {
            _ = try? exec("ROLLBACK;")
            throw error
        }
    }

    /// Append an audit row. Mirrors `db_audit` in the C kernel.
    public func appendAudit(action: String, details: String?) throws {
        let stmt = try prepare("INSERT INTO audit_log(action, details) VALUES(?, ?);")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, action)
        bindText(stmt, 2, details)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw TreasuryError.sqlite("audit insert failed")
        }
    }

    // MARK: - Generic query / insert helpers

    public func query<T>(_ sql: String,
                         bind: (LedgerDatabase, OpaquePointer) -> Void = { _, _ in },
                         _ map: (OpaquePointer) -> T) throws -> [T]
    {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(self, stmt)
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(map(stmt))
        }
        return out
    }

    public func queryOne<T>(_ sql: String,
                            bind: (LedgerDatabase, OpaquePointer) -> Void = { _, _ in },
                            map: (OpaquePointer) -> T) throws -> T?
    {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(self, stmt)
        if sqlite3_step(stmt) == SQLITE_ROW { return map(stmt) }
        return nil
    }

    /// Run an INSERT / UPDATE / DELETE; returns `last_insert_rowid()`.
    @discardableResult
    public func insert(_ sql: String,
                       bind: (LedgerDatabase, OpaquePointer) -> Void) throws -> Int64
    {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(self, stmt)
        if sqlite3_step(stmt) != SQLITE_DONE {
            let h = try handle()
            throw TreasuryError.sqlite(String(cString: sqlite3_errmsg(h)))
        }
        return sqlite3_last_insert_rowid(try handle())
    }

    /// Number of rows touched by the last write.
    public func changes() throws -> Int32 { sqlite3_changes(try handle()) }
}
