import Foundation
import SQLite3

public struct AuditService: Sendable {
    public let db: LedgerDatabase
    public init(db: LedgerDatabase) { self.db = db }

    public func recent(limit: Int = 100) async throws -> [AuditEvent] {
        try await db.query("""
            SELECT id, action, COALESCE(details, ''), created_at
            FROM audit_log ORDER BY id DESC LIMIT ?;
            """, bind: { _, stmt in sqlite3_bind_int(stmt, 1, Int32(limit)) }) { dbi, stmt in
            AuditEvent(
                id: sqlite3_column_int64(stmt, 0),
                action: dbi.text(stmt, 1),
                details: dbi.text(stmt, 2),
                createdAt: dbi.text(stmt, 3))
        }
    }

    public func append(action: String, details: String?) async throws {
        try await db.appendAudit(action: action, details: details)
    }
}
