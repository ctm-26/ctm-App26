import Foundation
import TreasuryKernel
import SQLite3

/// Drives live paper-trading against a `PriceFeed`. The engine is owned by the
/// UI layer; it polls the feed at a fixed cadence, builds candles, and runs
/// the selected strategy through the risk governor and paper broker on each
/// new bar. Trades and equity snapshots persist to the ledger DB so the
/// charts can read them back later.
public actor TradingEngine {
    public struct Config: Sendable {
        public var symbol: String
        public var granularity: Granularity
        public var pollInterval: TimeInterval
        public var historyBars: Int
        public init(symbol: String = "BTC-USD",
                    granularity: Granularity = .hour,
                    pollInterval: TimeInterval = 30,
                    historyBars: Int = 200)
        {
            self.symbol = symbol; self.granularity = granularity
            self.pollInterval = pollInterval; self.historyBars = historyBars
        }
    }

    public enum Status: Sendable, Equatable {
        case idle, running, stopped(reason: String)
    }

    public let db: LedgerDatabase
    public let portfolioId: Int64
    public let feed: PriceFeed
    public let governor: RiskGovernor
    public let broker: PaperBroker
    public var strategy: any Strategy
    public var config: Config

    private var status: Status = .idle
    private var pollTask: Task<Void, Never>?
    private(set) public var candles: [Candle] = []

    public init(db: LedgerDatabase, portfolioId: Int64, feed: PriceFeed,
                strategy: any Strategy, broker: PaperBroker,
                governor: RiskGovernor, config: Config = Config())
    {
        self.db = db; self.portfolioId = portfolioId
        self.feed = feed; self.strategy = strategy
        self.broker = broker; self.governor = governor
        self.config = config
    }

    public func currentStatus() -> Status { status }

    public func start() {
        guard status != .running else { return }
        status = .running
        let cfg = config
        pollTask = Task { [weak self] in
            while !(Task.isCancelled) {
                guard let self else { break }
                do {
                    try await self.tick()
                } catch {
                    await self.stop(reason: "feed error: \(error)")
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(cfg.pollInterval * 1_000_000_000))
            }
        }
    }

    public func stop(reason: String = "stopped") {
        pollTask?.cancel(); pollTask = nil
        status = .stopped(reason: reason)
    }

    /// One trading cycle: refresh history, evaluate strategy, optionally trade,
    /// persist equity sample.
    public func tick() async throws {
        let end = Date()
        let start = end.addingTimeInterval(
            -TimeInterval(config.granularity.rawValue * config.historyBars))
        candles = try await feed.candles(
            symbol: config.symbol, granularity: config.granularity,
            start: start, end: end)
        guard let last = candles.last else { return }

        broker.updateMark(symbol: config.symbol, price: last.close)
        let snap = broker.snapshot(at: last.time)
        governor.updateEquity(snap.equityCents)
        try await persistEquity(snap: snap, at: last.time)

        let ctx = StrategyContext(
            symbol: config.symbol, history: candles,
            position: snap.position(for: config.symbol),
            cashCents: snap.cashCents, equityCents: snap.equityCents)
        guard strategy.warmupOK(ctx) else { return }

        let decision = strategy.decide(ctx)
        switch decision {
        case .hold:
            return
        case .buy(let q, let reason):
            let req = q ?? defaultBuyQty(snap: snap, price: last.close)
            let order = Order(symbol: config.symbol, side: .buy, qty: req,
                              strategy: strategy.name, reason: reason)
            try await execute(order: order, lastPrice: last.close, snap: snap)
        case .sell(let q, let reason):
            let req = q ?? (snap.position(for: config.symbol)?.qty ?? 0)
            guard req > 0 else { return }
            let order = Order(symbol: config.symbol, side: .sell, qty: req,
                              strategy: strategy.name, reason: reason)
            try await execute(order: order, lastPrice: last.close, snap: snap)
        }
    }

    public func setStrategy(_ s: any Strategy) { strategy = s }
    public func setConfig(_ c: Config) { config = c }

    // MARK: - Persistence

    private func defaultBuyQty(snap: PaperBroker.Snapshot, price: Double) -> Double {
        let cap = Int64(Double(snap.equityCents) * governor.config.maxPositionPctEquity)
        let dollars = Double(min(cap, snap.cashCents)) / 100.0
        return price > 0 ? dollars / price : 0
    }

    private func execute(order: Order, lastPrice: Double,
                         snap: PaperBroker.Snapshot) async throws
    {
        switch governor.evaluate(order: order, lastPrice: lastPrice, portfolio: snap) {
        case .reject(let reason):
            // Governor-side rejection: risk limits / no cash / etc.
            try await db.appendAudit(
                action: "trade.reject.governor",
                details: "symbol=\(order.symbol) side=\(order.side.rawValue) reason=\(reason)")
        case .approve(let qty, let note):
            switch broker.execute(order: order, qtyBaseUnits: qty) {
            case .rejected(let reason):
                // Broker-side rejection: insufficient cash, no market price.
                // This should be rare now that the governor reserves fees,
                // but we still audit it distinctly from a governor reject so
                // operators can tell which gate said no.
                try await db.appendAudit(
                    action: "trade.reject.broker",
                    details: "symbol=\(order.symbol) side=\(order.side.rawValue) reason=\(reason)")
            case .filled(let fill):
                try await persistFill(fill)
                var details = "sym=\(order.symbol) qty=\(qty) px=\(lastPrice) strat=\(order.strategy ?? "?")"
                if let note = note { details += " note=\(note)" }
                try await db.appendAudit(
                    action: "trade.\(order.side.rawValue)",
                    details: details)
            }
        }
    }

    private func persistFill(_ fill: PaperFill) async throws {
        let isoFormatter = ISO8601DateFormatter()
        try await db.insert("""
            INSERT INTO paper_trades
            (portfolio_id, symbol, side, qty, price_cents, fee_cents, strategy, reason, executed_at)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, bind: { dbi, stmt in
            dbi.bindInt(stmt, 1, self.portfolioId)
            dbi.bindText(stmt, 2, fill.order.symbol)
            dbi.bindText(stmt, 3, fill.order.side.rawValue)
            dbi.bindDouble(stmt, 4, fill.filledQty)
            dbi.bindInt(stmt, 5, fill.priceCents)
            dbi.bindInt(stmt, 6, fill.feeCents)
            dbi.bindText(stmt, 7, fill.order.strategy)
            dbi.bindText(stmt, 8, fill.order.reason)
            dbi.bindText(stmt, 9, isoFormatter.string(from: fill.executedAt))
        })
    }

    private func persistEquity(snap: PaperBroker.Snapshot, at time: Date) async throws {
        let isoFormatter = ISO8601DateFormatter()
        try await db.insert("""
            INSERT OR REPLACE INTO paper_equity_points
            (portfolio_id, at, equity_cents, cash_cents) VALUES(?, ?, ?, ?);
            """, bind: { dbi, stmt in
            dbi.bindInt(stmt, 1, self.portfolioId)
            dbi.bindText(stmt, 2, isoFormatter.string(from: time))
            dbi.bindInt(stmt, 3, snap.equityCents)
            dbi.bindInt(stmt, 4, snap.cashCents)
        })
    }
}
