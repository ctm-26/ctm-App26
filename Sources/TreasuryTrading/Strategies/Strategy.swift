import Foundation

public enum StrategyDecision: Sendable, Equatable {
    case hold
    /// `qtyBaseUnits` may be `nil` to defer sizing to the risk governor.
    case buy(qtyBaseUnits: Double?, reason: String)
    case sell(qtyBaseUnits: Double?, reason: String)
}

public struct StrategyContext: Sendable {
    public let symbol: String
    public let history: [Candle]
    public let position: Position?
    public let cashCents: Int64
    public let equityCents: Int64

    public var lastClose: Double { history.last?.close ?? 0 }
    public var closes: [Double] { history.map { $0.close } }
    public var highs: [Double] { history.map { $0.high } }
    public var lows: [Double] { history.map { $0.low } }
}

public protocol Strategy: Sendable {
    /// Stable name; persisted on every trade in `paper_trades.strategy`.
    var name: String { get }
    /// One-line description for the UI.
    var summary: String { get }
    /// Whether the strategy should be evaluated at all on this bar.
    func warmupOK(_ ctx: StrategyContext) -> Bool
    /// The core decision. Implementations must be deterministic given the same
    /// history (this is what makes the audit log usable).
    func decide(_ ctx: StrategyContext) -> StrategyDecision
}

/// Catalog of built-in strategies. The order is the order shown in the UI.
public enum StrategyCatalog {
    public static func all() -> [any Strategy] {
        [
            SMACrossoverStrategy(),
            RSIReversionStrategy(),
            DonchianBreakoutStrategy(),
            DCAStrategy(),
        ]
    }
}
