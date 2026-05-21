import Foundation

/// Donchian channel breakout. Buy when close pierces the N-period high; exit
/// when it pierces the M-period low. Classic trend follower (Turtle style).
public struct DonchianBreakoutStrategy: Strategy {
    public let entryPeriod: Int
    public let exitPeriod: Int

    public var name: String { "donchian_\(entryPeriod)_\(exitPeriod)" }
    public var summary: String { "Donchian breakout (\(entryPeriod) hi / \(exitPeriod) lo)" }

    public init(entryPeriod: Int = 20, exitPeriod: Int = 10) {
        self.entryPeriod = entryPeriod; self.exitPeriod = exitPeriod
    }

    public func warmupOK(_ ctx: StrategyContext) -> Bool {
        ctx.history.count > max(entryPeriod, exitPeriod) + 1
    }

    public func decide(_ ctx: StrategyContext) -> StrategyDecision {
        let highs = ctx.highs, lows = ctx.lows
        let entryHi = Indicators.donchianHigh(highs, period: entryPeriod)
        let exitLo = Indicators.donchianLow(lows, period: exitPeriod)
        guard let lastIdx = ctx.history.indices.last,
              let prevIdx = ctx.history.indices.dropLast().last
        else { return .hold }
        let close = ctx.closes[lastIdx]
        let pos = ctx.position?.qty ?? 0

        if pos <= 0, let prevHi = entryHi[prevIdx], close > prevHi {
            return .buy(qtyBaseUnits: nil, reason: "close>\(String(format: "%.2f", prevHi))")
        }
        if pos > 0, let prevLo = exitLo[prevIdx], close < prevLo {
            return .sell(qtyBaseUnits: pos, reason: "close<\(String(format: "%.2f", prevLo))")
        }
        return .hold
    }
}
