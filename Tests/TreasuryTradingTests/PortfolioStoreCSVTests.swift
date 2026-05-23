import XCTest
@testable import TreasuryTrading
import TreasuryKernel

/// Verifies the CSV exporter on PortfolioStore.
final class PortfolioStoreCSVTests: XCTestCase {

    private func makeDB() throws -> LedgerDatabase {
        let path = NSTemporaryDirectory() + "treasury-csv-test-\(UUID().uuidString).db"
        return try LedgerDatabase(path: path)
    }

    /// Raw insert into paper_trades — we don't want to drag in the full engine
    /// just to seed rows for a string-export test.
    private func insertTrade(db: LedgerDatabase,
                             portfolioId: Int64,
                             symbol: String,
                             side: String,
                             qty: Double,
                             priceCents: Int64,
                             feeCents: Int64,
                             strategy: String,
                             reason: String,
                             executedAt: String) async throws {
        _ = try await db.insert("""
            INSERT INTO paper_trades(portfolio_id, symbol, side, qty,
                                     price_cents, fee_cents, strategy, reason,
                                     executed_at)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, bind: { dbi, stmt in
            dbi.bindInt(stmt, 1, portfolioId)
            dbi.bindText(stmt, 2, symbol)
            dbi.bindText(stmt, 3, side)
            dbi.bindDouble(stmt, 4, qty)
            dbi.bindInt(stmt, 5, priceCents)
            dbi.bindInt(stmt, 6, feeCents)
            dbi.bindText(stmt, 7, strategy)
            dbi.bindText(stmt, 8, reason)
            dbi.bindText(stmt, 9, executedAt)
        })
    }

    func testEmptyPortfolioExportsOnlyHeader() async throws {
        let db = try makeDB()
        let store = PortfolioStore(db: db)
        let p = try await store.createPortfolio(name: "empty-\(UUID().uuidString)",
                                                initialCashCents: 100_000_00)
        let csv = try await store.exportTradesCSV(portfolioId: p.id)
        XCTAssertEqual(csv, "executed_at,symbol,side,qty,price,fee,strategy,reason\n")
    }

    func testCSVQuotesAndEscapesReasonField() async throws {
        let db = try makeDB()
        let store = PortfolioStore(db: db)
        let p = try await store.createPortfolio(name: "esc-\(UUID().uuidString)",
                                                initialCashCents: 100_000_00)
        // Reason contains a comma and a literal " — RFC 4180 says the comma
        // requires the field to be quoted, and the " must be doubled.
        try await insertTrade(db: db,
                              portfolioId: p.id,
                              symbol: "BTC-USD",
                              side: "buy",
                              qty: 0.5,
                              priceCents: 50_000,  // $500.00
                              feeCents: 2_500,     // $25.00
                              strategy: "smaCross",
                              reason: "fast > slow, said \"go\"",
                              executedAt: "2026-05-23T12:00:00Z")
        let csv = try await store.exportTradesCSV(portfolioId: p.id)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 3) // header + 1 row + trailing empty
        XCTAssertEqual(lines[0], "executed_at,symbol,side,qty,price,fee,strategy,reason")
        // Expect the reason wrapped in "..." with the inner " doubled.
        // strategy is also quoted (its value has no commas/quotes so it's just
        // wrapped, no escaping needed).
        XCTAssertEqual(
            String(lines[1]),
            "2026-05-23T12:00:00Z,BTC-USD,buy,0.50000000,500.00,25.00,\"smaCross\",\"fast > slow, said \"\"go\"\"\""
        )
    }

    func testMultipleTradesOrderedByExecutedAtDesc() async throws {
        let db = try makeDB()
        let store = PortfolioStore(db: db)
        let p = try await store.createPortfolio(name: "multi-\(UUID().uuidString)",
                                                initialCashCents: 1_000_000_00)
        // Insert three trades in arbitrary order; the recentTrades query
        // orders by executed_at DESC.
        try await insertTrade(db: db, portfolioId: p.id, symbol: "AAA", side: "buy",
                              qty: 1, priceCents: 100_00, feeCents: 0,
                              strategy: "s", reason: "oldest",
                              executedAt: "2026-05-01T00:00:00Z")
        try await insertTrade(db: db, portfolioId: p.id, symbol: "CCC", side: "sell",
                              qty: 3, priceCents: 300_00, feeCents: 0,
                              strategy: "s", reason: "newest",
                              executedAt: "2026-05-03T00:00:00Z")
        try await insertTrade(db: db, portfolioId: p.id, symbol: "BBB", side: "buy",
                              qty: 2, priceCents: 200_00, feeCents: 0,
                              strategy: "s", reason: "middle",
                              executedAt: "2026-05-02T00:00:00Z")
        let csv = try await store.exportTradesCSV(portfolioId: p.id)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        // header + 3 rows + trailing empty
        XCTAssertEqual(lines.count, 5)
        XCTAssertTrue(lines[1].hasPrefix("2026-05-03T00:00:00Z,CCC,"),
                      "row 1 should be newest (CCC) — got \(lines[1])")
        XCTAssertTrue(lines[2].hasPrefix("2026-05-02T00:00:00Z,BBB,"),
                      "row 2 should be middle (BBB) — got \(lines[2])")
        XCTAssertTrue(lines[3].hasPrefix("2026-05-01T00:00:00Z,AAA,"),
                      "row 3 should be oldest (AAA) — got \(lines[3])")
    }
}
