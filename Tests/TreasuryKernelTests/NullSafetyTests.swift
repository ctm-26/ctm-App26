import XCTest
import SQLite3
@testable import TreasuryKernel

/// Pre-fix, `String(cString: sqlite3_column_text(stmt, idx))` traps the
/// process on NULL. These tests insert a row with a NULL TEXT column and
/// confirm the new `text` / `optionalText` helpers return safely.
final class NullSafetyTests: XCTestCase {

    func makeDB() async throws -> LedgerDatabase {
        let path = NSTemporaryDirectory() + "treasury-nullsafe-\(UUID().uuidString).db"
        return try LedgerDatabase(path: path)
    }

    /// Insert an audit row whose `details` column is NULL (skipping the
    /// COALESCE in AuditService.recent), then read it back via the generic
    /// `query` helper. `optionalText` must return nil; `text` (with the
    /// default fallback) must return "".
    func testOptionalTextReturnsNilForNullColumn() async throws {
        let db = try await makeDB()
        // Insert a row with explicit NULL details. We can't easily inject via
        // appendAudit (which always binds the value, even if nil), so use
        // exec directly to write a literal NULL.
        try await db.exec(
            "INSERT INTO audit_log(action, details) VALUES('test.null', NULL);")

        struct Row { let action: String; let details: String?; let fallback: String }
        let rows: [Row] = try await db.query(
            "SELECT action, details, details FROM audit_log WHERE action='test.null';"
        ) { dbi, stmt in
            Row(action: dbi.text(stmt, 0),
                details: dbi.optionalText(stmt, 1),
                fallback: dbi.text(stmt, 2, default: "<missing>"))
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.action, "test.null")
        XCTAssertNil(rows.first?.details,
                     "optionalText must surface NULL as Swift nil, not as empty string")
        XCTAssertEqual(rows.first?.fallback, "<missing>",
                       "text(default:) must use the fallback for NULL columns")
    }

    /// Smoke test that an unrelated AuditService.recent() call (which uses
    /// COALESCE under the hood) still works after the refactor and doesn't
    /// crash even when an underlying row happened to have a NULL details.
    func testAuditServiceRecentDoesNotCrashOnNull() async throws {
        let db = try await makeDB()
        try await db.exec(
            "INSERT INTO audit_log(action, details) VALUES('a', NULL);")
        try await db.exec(
            "INSERT INTO audit_log(action, details) VALUES('b', 'has-details');")
        let events = try await AuditService(db: db).recent(limit: 10)
        XCTAssertGreaterThanOrEqual(events.count, 2)
        // The 'a' row's details should be the empty string thanks to the
        // SQL-level COALESCE; the service-level fallback never trips.
        let a = events.first { $0.action == "a" }
        XCTAssertNotNil(a)
        XCTAssertEqual(a?.details, "")
    }
}
