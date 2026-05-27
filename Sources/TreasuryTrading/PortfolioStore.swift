import Foundation
import TreasuryKernel
import SQLite3

/// Persistence for paper portfolios, equity samples, and trade history.
/// Reads only — the engine writes; the UI reads.
public struct PortfolioStore: Sendable {
    public let db: LedgerDatabase
    public init(db: LedgerDatabase) { self.db = db }

    public struct PortfolioRow: Identifiable, Sendable {
        public let id: Int64
        public let name: String
        public let cashCents: Int64
        public let createdAt: String
    }

    public func portfolios() async throws -> [PortfolioRow] {
        try await db.query("""
            SELECT id, name, cash_cents, created_at
            FROM paper_portfolios ORDER BY name;
            """) { dbi, stmt in
            PortfolioRow(id: sqlite3_column_int64(stmt, 0),
                         name: dbi.text(stmt, 1),
                         cashCents: sqlite3_column_int64(stmt, 2),
                         createdAt: dbi.text(stmt, 3))
        }
    }

    public func createPortfolio(name: String, initialCashCents: Int64) async throws -> PortfolioRow {
        let id = try await db.insert("""
            INSERT INTO paper_portfolios(name, cash_cents) VALUES(?, ?);
            """, bind: { dbi, stmt in
            dbi.bindText(stmt, 1, name); dbi.bindInt(stmt, 2, initialCashCents)
        })
        try await db.appendAudit(action: "paper.portfolio.create",
                                 details: "name=\(name) cash=\(initialCashCents)")
        return PortfolioRow(id: id, name: name,
                            cashCents: initialCashCents, createdAt: "")
    }

    public func equitySeries(portfolioId: Int64, limit: Int = 1000) async throws -> [EquityPoint] {
        try await db.query("""
            SELECT at, equity_cents, cash_cents
            FROM paper_equity_points WHERE portfolio_id = ?
            ORDER BY at DESC LIMIT ?;
            """, bind: { dbi, stmt in
            dbi.bindInt(stmt, 1, portfolioId)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }) { dbi, stmt in
            let iso = ISO8601DateFormatter()
            let at = iso.date(from: dbi.text(stmt, 0)) ?? Date()
            return EquityPoint(
                time: at,
                equity: Money(cents: sqlite3_column_int64(stmt, 1)),
                cash: Money(cents: sqlite3_column_int64(stmt, 2)))
        }.reversed()
    }

    public func recentTrades(portfolioId: Int64, limit: Int = 200) async throws -> [TradeRow] {
        try await db.query("""
            SELECT id, symbol, side, qty, price_cents, fee_cents,
                   COALESCE(strategy, ''), COALESCE(reason, ''), executed_at
            FROM paper_trades WHERE portfolio_id = ?
            ORDER BY executed_at DESC, id DESC LIMIT ?;
            """, bind: { dbi, stmt in
            dbi.bindInt(stmt, 1, portfolioId); sqlite3_bind_int(stmt, 2, Int32(limit))
        }) { dbi, stmt in
            TradeRow(
                id: sqlite3_column_int64(stmt, 0),
                symbol: dbi.text(stmt, 1),
                side: dbi.text(stmt, 2),
                qty: sqlite3_column_double(stmt, 3),
                priceCents: sqlite3_column_int64(stmt, 4),
                feeCents: sqlite3_column_int64(stmt, 5),
                strategy: dbi.text(stmt, 6),
                reason: dbi.text(stmt, 7),
                executedAt: dbi.text(stmt, 8))
        }
    }

    public struct TradeRow: Identifiable, Sendable {
        public let id: Int64
        public let symbol: String
        public let side: String
        public let qty: Double
        public let priceCents: Int64
        public let feeCents: Int64
        public let strategy: String
        public let reason: String
        public let executedAt: String
    }

    /// CSV-format string of every trade for a portfolio. Header row:
    ///   executed_at,symbol,side,qty,price,fee,strategy,reason
    /// Prices and fees are formatted as decimal dollars (not cents).
    /// `qty` uses full precision (no rounding).
    /// Strategy and reason are double-quoted with internal quotes escaped.
    public func exportTradesCSV(portfolioId: Int64) async throws -> String {
        // `recentTrades` binds limit as Int32, so we use a high cap rather
        // than Int.max (which would overflow when narrowed).
        let rows = try await recentTrades(portfolioId: portfolioId, limit: 1_000_000)
        var out = "executed_at,symbol,side,qty,price,fee,strategy,reason\n"
        for r in rows {
            let qty = String(format: "%.8f", r.qty)
            let price = Money(cents: r.priceCents).plainString
            let fee = Money(cents: r.feeCents).plainString
            let strategy = csvQuote(r.strategy)
            let reason = csvQuote(r.reason)
            out += "\(r.executedAt),\(r.symbol),\(r.side),\(qty),\(price),\(fee),\(strategy),\(reason)\n"
        }
        return out
    }

    private func csvQuote(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
