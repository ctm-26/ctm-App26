import Foundation
import TreasuryKernel

/// Deterministic single-symbol, single-strategy backtester. Walks candles in
/// order, marks the broker to the close of each bar, then asks the strategy
/// for a decision. Designed to be fast enough to scrub interactively on iPad.
public struct Backtester: Sendable {
    public let strategy: any Strategy
    public let symbol: String
    public let initialCashCents: Int64
    public let feeRate: Double
    public let governorConfig: RiskGovernor.Config

    public init(strategy: any Strategy,
                symbol: String,
                initialCashCents: Int64 = 10_000_00,
                feeRate: Double = 0.0040,
                governorConfig: RiskGovernor.Config = .balanced)
    {
        self.strategy = strategy; self.symbol = symbol
        self.initialCashCents = initialCashCents; self.feeRate = feeRate
        self.governorConfig = governorConfig
    }

    public func run(candles: [Candle]) -> BacktestResult {
        let broker = PaperBroker(initialCashCents: initialCashCents, feeRate: feeRate)
        let governor = RiskGovernor(config: governorConfig)
        var equityCurve: [EquityPoint] = []
        var trades: [PaperFill] = []

        for i in 0..<candles.count {
            let bar = candles[i]
            broker.updateMark(symbol: symbol, price: bar.close)
            let snap = broker.snapshot(at: bar.time)
            governor.updateEquity(snap.equityCents)
            equityCurve.append(EquityPoint(time: bar.time,
                                           equity: Money(cents: snap.equityCents),
                                           cash: Money(cents: snap.cashCents)))
            let window = Array(candles[0...i])
            let ctx = StrategyContext(
                symbol: symbol, history: window,
                position: snap.position(for: symbol),
                cashCents: snap.cashCents, equityCents: snap.equityCents)
            guard strategy.warmupOK(ctx) else { continue }
            let decision = strategy.decide(ctx)
            switch decision {
            case .hold:
                continue
            case .buy(let q, let reason):
                let requestedQty = q ?? defaultBuyQty(snap: snap, price: bar.close)
                let order = Order(symbol: symbol, side: .buy,
                                  qty: requestedQty,
                                  strategy: strategy.name,
                                  reason: reason)
                switch governor.evaluate(order: order, lastPrice: bar.close, portfolio: snap) {
                case .approve(let qty):
                    if let fill = broker.execute(order: order, qtyBaseUnits: qty, at: bar.time) {
                        trades.append(fill)
                    }
                case .reject:
                    continue
                }
            case .sell(let q, let reason):
                let requestedQty = q ?? (snap.position(for: symbol)?.qty ?? 0)
                guard requestedQty > 0 else { continue }
                let order = Order(symbol: symbol, side: .sell,
                                  qty: requestedQty,
                                  strategy: strategy.name,
                                  reason: reason)
                switch governor.evaluate(order: order, lastPrice: bar.close, portfolio: snap) {
                case .approve(let qty):
                    if let fill = broker.execute(order: order, qtyBaseUnits: qty, at: bar.time) {
                        trades.append(fill)
                    }
                case .reject:
                    continue
                }
            }
        }
        if let lastBar = candles.last {
            broker.updateMark(symbol: symbol, price: lastBar.close)
            let snap = broker.snapshot(at: lastBar.time)
            equityCurve.append(EquityPoint(time: lastBar.time,
                                           equity: Money(cents: snap.equityCents),
                                           cash: Money(cents: snap.cashCents)))
        }
        return BacktestResult(
            equityCurve: equityCurve, trades: trades,
            stats: stats(curve: equityCurve, trades: trades))
    }

    private func defaultBuyQty(snap: PaperBroker.Snapshot, price: Double) -> Double {
        let cap = Int64(Double(snap.equityCents) * governorConfig.maxPositionPctEquity)
        let dollars = Double(min(cap, snap.cashCents)) / 100.0
        return price > 0 ? dollars / price : 0
    }

    private func stats(curve: [EquityPoint], trades: [PaperFill]) -> BacktestStats {
        let initial = Money(cents: initialCashCents)
        guard let last = curve.last else {
            return BacktestStats(initialEquity: initial, finalEquity: initial,
                                 totalReturnPct: 0, maxDrawdownPct: 0,
                                 tradeCount: trades.count, winRate: 0, sharpe: 0)
        }
        let final = last.equity
        let ret = Double(final.cents - initial.cents) / max(Double(initial.cents), 1)
        var peak: Int64 = initial.cents
        var maxDD = 0.0
        var returns: [Double] = []
        var prev = initial.cents
        for p in curve {
            peak = max(peak, p.equity.cents)
            if peak > 0 {
                let dd = 1.0 - Double(p.equity.cents) / Double(peak)
                if dd > maxDD { maxDD = dd }
            }
            if prev > 0 {
                returns.append(Double(p.equity.cents - prev) / Double(prev))
            }
            prev = p.equity.cents
        }
        let mean = returns.isEmpty ? 0 : returns.reduce(0, +) / Double(returns.count)
        let variance = returns.isEmpty ? 0
            : returns.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(returns.count)
        let stdev = variance.squareRoot()
        let sharpe = stdev > 0 ? (mean / stdev) * (252.0).squareRoot() : 0

        // win rate: pair adjacent buy/sell on the same symbol.
        var wins = 0, losses = 0
        var stack: [Int64] = []
        for t in trades {
            if t.order.side == .buy { stack.append(t.priceCents) }
            else if let entry = stack.popLast() {
                if t.priceCents > entry { wins += 1 } else { losses += 1 }
            }
        }
        let totalClosed = wins + losses
        let winRate = totalClosed > 0 ? Double(wins) / Double(totalClosed) : 0

        return BacktestStats(
            initialEquity: initial, finalEquity: final,
            totalReturnPct: ret, maxDrawdownPct: maxDD,
            tradeCount: trades.count, winRate: winRate, sharpe: sharpe)
    }
}
