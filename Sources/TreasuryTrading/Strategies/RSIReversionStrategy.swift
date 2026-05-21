import Foundation

/// Mean-reversion: buy when RSI dips below `oversold`, exit when it crosses back
/// above `cover`. Conservative defaults; works best with daily bars on liquid pairs.
public struct RSIReversionStrategy: Strategy {
    public let period: Int
    public let oversold: Double
    public let cover: Double

    public var name: String { "rsi_reversion_\(period)" }
    public var summary: String { "RSI(\(period)) buy<\(Int(oversold)) / cover>\(Int(cover))" }

    public init(period: Int = 14, oversold: Double = 30, cover: Double = 55) {
        self.period = period; self.oversold = oversold; self.cover = cover
    }

    public func warmupOK(_ ctx: StrategyContext) -> Bool { ctx.history.count > period + 1 }

    public func decide(_ ctx: StrategyContext) -> StrategyDecision {
        let rsi = Indicators.rsi(ctx.closes, period: period)
        guard let v = rsi.last ?? nil else { return .hold }
        let pos = ctx.position?.qty ?? 0
        if pos <= 0, v < oversold {
            return .buy(qtyBaseUnits: nil, reason: "rsi=\(String(format: "%.1f", v)) below \(Int(oversold))")
        }
        if pos > 0, v > cover {
            return .sell(qtyBaseUnits: pos, reason: "rsi=\(String(format: "%.1f", v)) above \(Int(cover))")
        }
        return .hold
    }
}
