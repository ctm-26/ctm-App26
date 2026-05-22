import Foundation
import SQLite3

public struct ReportService: Sendable {
    public let db: LedgerDatabase
    public init(db: LedgerDatabase) { self.db = db }

    public func monthly(_ month: String) async throws -> MonthlyReport {
        guard DateNormalizer.validYearMonth(month) else {
            throw TreasuryError.validation("invalid month '\(month)' (expect YYYY-MM)")
        }
        struct Summary { let income: Int64; let spending: Int64; let count: Int }
        let summary: Summary = try await db.queryOne("""
            SELECT
              COALESCE(SUM(CASE WHEN amount_cents > 0 THEN amount_cents ELSE 0 END), 0),
              COALESCE(SUM(CASE WHEN amount_cents < 0 THEN amount_cents ELSE 0 END), 0),
              COUNT(*)
            FROM transactions WHERE substr(date,1,7) = ?;
            """, bind: { dbi, stmt in dbi.bindText(stmt, 1, month) },
            map: { _, stmt in
                Summary(income: sqlite3_column_int64(stmt, 0),
                        spending: sqlite3_column_int64(stmt, 1),
                        count: Int(sqlite3_column_int(stmt, 2)))
            }) ?? Summary(income: 0, spending: 0, count: 0)
        let income = summary.income, spending = summary.spending, count = summary.count

        let byCategory: [CategoryRollup] = try await db.query("""
            SELECT COALESCE(c.name, '(unknown)') AS cat, SUM(t.amount_cents), COUNT(*)
            FROM transactions t
            LEFT JOIN categories c ON c.id = t.category_id
            WHERE substr(t.date,1,7) = ?
            GROUP BY cat ORDER BY SUM(t.amount_cents) ASC;
            """, bind: { dbi, stmt in dbi.bindText(stmt, 1, month) }) { dbi, stmt in
            CategoryRollup(name: dbi.text(stmt, 0),
                           amount: Money(cents: sqlite3_column_int64(stmt, 1)),
                           count: Int(sqlite3_column_int(stmt, 2)))
        }

        let byAccount: [AccountRollup] = try await db.query("""
            SELECT a.name, SUM(t.amount_cents), COUNT(*)
            FROM transactions t JOIN accounts a ON a.id = t.account_id
            WHERE substr(t.date,1,7) = ?
            GROUP BY a.name ORDER BY a.name;
            """, bind: { dbi, stmt in dbi.bindText(stmt, 1, month) }) { dbi, stmt in
            AccountRollup(name: dbi.text(stmt, 0),
                          net: Money(cents: sqlite3_column_int64(stmt, 1)),
                          count: Int(sqlite3_column_int(stmt, 2)))
        }

        try await db.appendAudit(action: "report.month",
                                 details: "month=\(month) tx=\(count)")

        return MonthlyReport(month: month, transactionCount: count,
                             income: Money(cents: income),
                             spending: Money(cents: spending),
                             byCategory: byCategory, byAccount: byAccount)
    }

    public struct DailyPoint: Identifiable, Sendable {
        public var id: String { date }
        public let date: String
        public let net: Money
    }

    /// Daily cumulative net across all accounts. Useful for the timeline chart.
    public func dailyCumulative(months: Int = 12) async throws -> [DailyPoint] {
        let rows: [(String, Int64)] = try await db.query("""
            SELECT date, SUM(amount_cents) FROM transactions
            WHERE date >= date('now', ?)
            GROUP BY date ORDER BY date;
            """, bind: { dbi, stmt in dbi.bindText(stmt, 1, "-\(months) months") }) { dbi, stmt in
            (dbi.text(stmt, 0),
             sqlite3_column_int64(stmt, 1))
        }
        var running: Int64 = 0
        return rows.map { (date, delta) in
            running += delta
            return DailyPoint(date: date, net: Money(cents: running))
        }
    }

    public struct MonthlyTotal: Identifiable, Sendable {
        public var id: String { month }
        public let month: String
        public let income: Money
        public let spending: Money
        public var net: Money { Money(cents: income.cents + spending.cents) }
    }

    public func months(last n: Int = 6) async throws -> [MonthlyTotal] {
        try await db.query("""
            SELECT substr(date,1,7) AS m,
                   COALESCE(SUM(CASE WHEN amount_cents > 0 THEN amount_cents ELSE 0 END), 0),
                   COALESCE(SUM(CASE WHEN amount_cents < 0 THEN amount_cents ELSE 0 END), 0)
            FROM transactions
            WHERE date >= date('now', ?)
            GROUP BY m ORDER BY m;
            """, bind: { dbi, stmt in dbi.bindText(stmt, 1, "-\(n) months") }) { dbi, stmt in
            MonthlyTotal(
                month: dbi.text(stmt, 0),
                income: Money(cents: sqlite3_column_int64(stmt, 1)),
                spending: Money(cents: sqlite3_column_int64(stmt, 2)))
        }
    }
}
