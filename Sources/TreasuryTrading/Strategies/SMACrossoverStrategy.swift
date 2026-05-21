import Foundation

/// Classic moving-average crossover.
/// Buy when fast SMA crosses above slow SMA; flatten when it crosses below.
/// Defaults: fast=20, slow=50 (intended for hourly or daily bars).
public struct SMACrossoverStrategy: Strategy {
    public let fast: Int
    public let slow: Int

    public var name: String { "sma_crossover_\(fast)_\(slow)" }
    public var summary: String { "Fast/slow SMA crossover (\(fast) vs \(slow))" }

    public init(fast: Int = 20, slow: Int = 50) {
        precondition(fast > 1 && slow > fast)
        self.fast = fast; self.slow = slow
    }

    public func warmupOK(_ ctx: StrategyContext) -> Bool { ctx.history.count > slow + 1 }

    public func decide(_ ctx: StrategyContext) -> StrategyDecision {
        let closes = ctx.closes
        let fastSma = Indicators.sma(closes, period: fast)
        let slowSma = Indicators.sma(closes, period: slow)
        let n = closes.count
        guard n >= 2,
              let f0 = fastSma[n - 2], let f1 = fastSma[n - 1],
              let s0 = slowSma[n - 2], let s1 = slowSma[n - 1]
        else { return .hold }

        let crossedUp = f0 <= s0 && f1 > s1
        let crossedDown = f0 >= s0 && f1 < s1
        let position = ctx.position?.qty ?? 0

        if crossedUp, position <= 0 {
            return .buy(qtyBaseUnits: nil, reason: "fast crossed above slow")
        }
        if crossedDown, position > 0 {
            return .sell(qtyBaseUnits: position, reason: "fast crossed below slow")
        }
        return .hold
    }
}
