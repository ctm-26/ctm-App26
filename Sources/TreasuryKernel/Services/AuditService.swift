import Foundation
import SQLite3

// TODO(v0.3): consider index on audit_log(action) if rows exceed 100k

public struct AuditService: Sendable {
    public let db: LedgerDatabase
    public init(db: LedgerDatabase) { self.db = db }

    /// Legacy entrypoint, preserved so existing callers keep compiling.
    public func recent(limit: Int = 100) async throws -> [AuditEvent] {
        try await recent(limit: limit, beforeId: nil, action: nil, search: nil)
    }

    /// Filterable, cursor-paginated audit query.
    ///
    /// - Parameters:
    ///   - limit: max rows to return.
    ///   - beforeId: when non-nil, only rows with `id < beforeId` are returned.
    ///     Used by the UI to fetch the next (older) page.
    ///   - action: when non-nil, exact-match on the `action` column (machine
    ///     identifiers are case-sensitive).
    ///   - search: when non-nil and non-empty, case-insensitive substring match
    ///     on the `details` column.
    public func recent(limit: Int = 100,
                       beforeId: Int64? = nil,
                       action: String? = nil,
                       search: String? = nil) async throws -> [AuditEvent] {
        var sql = "SELECT id, action, COALESCE(details, ''), created_at FROM audit_log"
        var clauses: [String] = []
        if beforeId != nil { clauses.append("id < ?") }
        if action != nil { clauses.append("action = ?") }
        let trimmedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines)
        let useSearch = (trimmedSearch?.isEmpty == false)
        if useSearch { clauses.append("details LIKE ('%' || ? || '%') COLLATE NOCASE") }
        if !clauses.isEmpty {
            sql += " WHERE " + clauses.joined(separator: " AND ")
        }
        sql += " ORDER BY id DESC LIMIT ?;"

        let capturedBeforeId = beforeId
        let capturedAction = action
        let capturedSearch = trimmedSearch

        return try await db.query(sql, bind: { dbi, stmt in
            var idx: Int32 = 1
            if let b = capturedBeforeId {
                sqlite3_bind_int64(stmt, idx, b)
                idx += 1
            }
            if let a = capturedAction {
                dbi.bindText(stmt, idx, a)
                idx += 1
            }
            if useSearch, let s = capturedSearch {
                dbi.bindText(stmt, idx, s)
                idx += 1
            }
            sqlite3_bind_int(stmt, idx, Int32(limit))
        }) { dbi, stmt in
            AuditEvent(
                id: sqlite3_column_int64(stmt, 0),
                action: dbi.text(stmt, 1),
                details: dbi.text(stmt, 2),
                createdAt: dbi.text(stmt, 3))
        }
    }

    /// Distinct action strings present in the log, sorted alphabetically.
    /// Used by the UI to populate the filter menu.
    public func actions() async throws -> [String] {
        try await db.query("""
            SELECT DISTINCT action FROM audit_log
            WHERE action IS NOT NULL
            ORDER BY action ASC;
            """) { dbi, stmt in
            dbi.text(stmt, 0)
        }
    }

    public func append(action: String, details: String?) async throws {
        try await db.appendAudit(action: action, details: details)
    }
}
