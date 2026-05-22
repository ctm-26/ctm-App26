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
    /// Periods per year for Sharpe annualization. Defaults to 252 (equities).
    /// Pass `Granularity.barsPerYear` for crypto.
    public let barsPerYear: Double

    public init(strategy: any Strategy,
                symbol: String,
                initialCashCents: Int64 = 10_000_00,
                feeRate: Double = 0.0040,
                governorConfig: RiskGovernor.Config = .balanced,
                barsPerYear: Double = 252)
    {
        self.strategy = strategy; self.symbol = symbol
        self.initialCashCents = initialCashCents; self.feeRate = feeRate
        self.governorConfig = governorConfig
        self.barsPerYear = barsPerYear
    }

    public func run(candles: [Candle]) -> BacktestResult {
        let broker = PaperBroker(initialCashCents: initialCashCents, feeRate: feeRate)
        let governor = RiskGovernor(config: governorConfig, feeRate: feeRate)
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
                case .approve(let qty, _):
                    if case .filled(let fill) = broker.execute(
                        order: order, qtyBaseUnits: qty, at: bar.time)
                    {
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
                case .approve(let qty, _):
                    if case .filled(let fill) = broker.execute(
                        order: order, qtyBaseUnits: qty, at: bar.time)
                    {
                        trades.append(fill)
                    }
                case .reject:
                    continue
                }
            }
        }
        // Note: we deliberately do NOT append a final equity point here —
        // the in-loop append already covers the last bar. Adding a duplicate
        // sample double-counted the last bar in earlier versions.
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
        let sharpe = stdev > 0 ? (mean / stdev) * barsPerYear.squareRoot() : 0

        // Win rate, FIFO at unit granularity. Each buy pushes its (price, qty)
        // onto a queue; each sell walks the queue head-first, comparing the
        // sell price against the cost basis of each unit consumed. We tally
        // wins/losses by unit count (not by trade), so a single sell can
        // split into multiple wins+losses if it spans multiple lots.
        struct Lot { var priceCents: Int64; var qty: Double }
        var queue: [Lot] = []
        var winUnits: Double = 0
        var lossUnits: Double = 0
        for t in trades {
            if t.order.side == .buy {
                queue.append(Lot(priceCents: t.priceCents, qty: t.filledQty))
            } else {
                var remaining = t.filledQty
                while remaining > 0 && !queue.isEmpty {
                    let head = queue[0]
                    let take = min(head.qty, remaining)
                    if t.priceCents > head.priceCents { winUnits += take }
                    else if t.priceCents < head.priceCents { lossUnits += take }
                    // break-even ticks neither bucket
                    remaining -= take
                    if take >= head.qty {
                        queue.removeFirst()
                    } else {
                        queue[0].qty -= take
                    }
                }
            }
        }
        let totalUnits = winUnits + lossUnits
        let winRate = totalUnits > 0 ? winUnits / totalUnits : 0

        return BacktestStats(
            initialEquity: initial, finalEquity: final,
            totalReturnPct: ret, maxDrawdownPct: maxDD,
            tradeCount: trades.count, winRate: winRate, sharpe: sharpe)
    }
}
