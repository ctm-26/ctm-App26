import Foundation
import TreasuryKernel

public struct Candle: Equatable, Hashable, Codable, Sendable {
    public let time: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double
    public init(time: Date, open: Double, high: Double, low: Double,
                close: Double, volume: Double) {
        self.time = time; self.open = open; self.high = high
        self.low = low; self.close = close; self.volume = volume
    }
}

public enum OrderSide: String, Codable, Sendable { case buy, sell }

public struct Order: Hashable, Sendable {
    public let id: UUID
    public let symbol: String
    public let side: OrderSide
    /// Quantity expressed in base currency units (e.g. BTC). Always positive.
    public let qty: Double
    public let strategy: String?
    public let reason: String?
    public init(symbol: String, side: OrderSide, qty: Double,
                strategy: String? = nil, reason: String? = nil) {
        self.id = UUID(); self.symbol = symbol; self.side = side
        self.qty = qty; self.strategy = strategy; self.reason = reason
    }
}

public struct Position: Identifiable, Hashable, Sendable {
    public var id: String { symbol }
    public let symbol: String
    public var qty: Double
    /// Average cost in cents per unit.
    public var avgCostCents: Int64
    public var marketPrice: Double?

    public func unrealizedPnL() -> Money? {
        guard let p = marketPrice else { return nil }
        let costPerUnit = Double(avgCostCents) / 100.0
        let pnl = (p - costPerUnit) * qty
        return Money(cents: Int64(pnl * 100.0))
    }
}

public struct PaperFill: Identifiable, Sendable {
    public let id: UUID
    public let order: Order
    public let priceCents: Int64
    public let feeCents: Int64
    public let executedAt: Date
}

public struct EquityPoint: Identifiable, Hashable, Sendable {
    public var id: Date { time }
    public let time: Date
    public let equity: Money
    public let cash: Money
}

public struct BacktestStats: Sendable {
    public let initialEquity: Money
    public let finalEquity: Money
    public let totalReturnPct: Double
    public let maxDrawdownPct: Double
    public let tradeCount: Int
    public let winRate: Double           // 0...1
    public let sharpe: Double            // annualized, naive
    public init(initialEquity: Money, finalEquity: Money, totalReturnPct: Double,
                maxDrawdownPct: Double, tradeCount: Int, winRate: Double, sharpe: Double) {
        self.initialEquity = initialEquity; self.finalEquity = finalEquity
        self.totalReturnPct = totalReturnPct; self.maxDrawdownPct = maxDrawdownPct
        self.tradeCount = tradeCount; self.winRate = winRate; self.sharpe = sharpe
    }
}

public struct BacktestResult: Sendable {
    public let equityCurve: [EquityPoint]
    public let trades: [PaperFill]
    public let stats: BacktestStats
}
