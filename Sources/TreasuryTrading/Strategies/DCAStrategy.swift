import Foundation
import TreasuryKernel

/// Dollar-cost averaging. Ignores price; buys a fixed cash amount every
/// `intervalBars` bars. Fires at bars intervalBars, 2*intervalBars, …
/// (bar 0 is skipped — we have no history yet). This is the baseline every
/// other strategy is implicitly competing against.
public struct DCAStrategy: Strategy {
    public let intervalBars: Int
    public let cashPerBuyCents: Int64

    public var name: String { "dca_\(intervalBars)_\(cashPerBuyCents)" }
    public var summary: String {
        "DCA every \(intervalBars) bars @ \(Money(cents: cashPerBuyCents).plainString)"
    }

    public init(intervalBars: Int = 24, cashPerBuyCents: Int64 = 10_000) {
        self.intervalBars = intervalBars
        self.cashPerBuyCents = cashPerBuyCents
    }

    public func warmupOK(_ ctx: StrategyContext) -> Bool { !ctx.history.isEmpty }

    public func decide(_ ctx: StrategyContext) -> StrategyDecision {
        // Use bar count as a stable cadence so the same history always fires the
        // same trades. Skip bar 0 — 0 % anything is 0, which would otherwise
        // fire a buy on the very first tick before any history exists.
        let idx = ctx.history.count - 1
        guard idx > 0, idx % intervalBars == 0 else { return .hold }
        guard ctx.lastClose > 0 else { return .hold }
        let cashAvailable = ctx.cashCents
        let target = min(cashAvailable, cashPerBuyCents)
        guard target > 0 else { return .hold }
        let qty = (Double(target) / 100.0) / ctx.lastClose
        return .buy(qtyBaseUnits: qty, reason: "scheduled DCA")
    }
}
