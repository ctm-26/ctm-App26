import Foundation
import TreasuryKernel

/// Hard limits the strategy can't bypass. Every order goes through `evaluate`.
/// If the governor trips (max drawdown, daily loss, etc.) it sets `tripped` and
/// rejects all subsequent orders for the session.
public final class RiskGovernor: @unchecked Sendable {
    public struct Config: Sendable {
        /// Max % of equity that can be allocated to a single new position.
        public var maxPositionPctEquity: Double
        /// Hard cap on number of simultaneous open positions.
        public var maxOpenPositions: Int
        /// Stop trading for the session if equity dips this far below the
        /// session's peak. 0.20 = 20%.
        public var maxDrawdownPct: Double
        /// Stop trading if cumulative session P&L hits this loss (positive number).
        public var dailyLossLimitCents: Int64
        /// Don't deploy below this cash reserve.
        public var minCashReserveCents: Int64

        public static let conservative = Config(
            maxPositionPctEquity: 0.10,
            maxOpenPositions: 3,
            maxDrawdownPct: 0.15,
            dailyLossLimitCents: 50_00,
            minCashReserveCents: 0)

        public static let balanced = Config(
            maxPositionPctEquity: 0.25,
            maxOpenPositions: 5,
            maxDrawdownPct: 0.25,
            dailyLossLimitCents: 200_00,
            minCashReserveCents: 0)

        public init(maxPositionPctEquity: Double, maxOpenPositions: Int,
                    maxDrawdownPct: Double, dailyLossLimitCents: Int64,
                    minCashReserveCents: Int64)
        {
            self.maxPositionPctEquity = maxPositionPctEquity
            self.maxOpenPositions = maxOpenPositions
            self.maxDrawdownPct = maxDrawdownPct
            self.dailyLossLimitCents = dailyLossLimitCents
            self.minCashReserveCents = minCashReserveCents
        }
    }

    public enum Decision: Equatable, Sendable {
        case approve(qtyBaseUnits: Double)
        case reject(reason: String)
    }

    public let config: Config
    public private(set) var tripped: Bool = false
    public private(set) var tripReason: String? = nil
    public private(set) var peakEquityCents: Int64 = 0
    public private(set) var sessionStartCents: Int64 = 0

    public init(config: Config) { self.config = config }

    /// Update the running peak; call this once per equity sample.
    public func updateEquity(_ equityCents: Int64) {
        if sessionStartCents == 0 { sessionStartCents = equityCents }
        peakEquityCents = max(peakEquityCents, equityCents)
        let drawdown = peakEquityCents > 0
            ? 1.0 - (Double(equityCents) / Double(peakEquityCents))
            : 0
        if drawdown >= config.maxDrawdownPct {
            trip("max drawdown reached: \(Int(drawdown * 100))%")
        }
        let lossFromStart = sessionStartCents - equityCents
        if lossFromStart >= config.dailyLossLimitCents,
           config.dailyLossLimitCents > 0
        {
            trip("daily loss limit hit (\(Money(cents: lossFromStart).plainString))")
        }
    }

    public func evaluate(order: Order,
                         lastPrice: Double,
                         portfolio: PaperBroker.Snapshot) -> Decision
    {
        if tripped { return .reject(reason: "risk governor tripped: \(tripReason ?? "?")") }
        guard lastPrice > 0 else { return .reject(reason: "no market price") }

        switch order.side {
        case .buy:
            if portfolio.openPositions >= config.maxOpenPositions,
               portfolio.position(for: order.symbol) == nil
            {
                return .reject(reason: "would exceed maxOpenPositions=\(config.maxOpenPositions)")
            }
            let cashLimit = max(portfolio.cashCents - config.minCashReserveCents, 0)
            let positionLimit = Int64(Double(portfolio.equityCents) * config.maxPositionPctEquity)
            let maxSpendCents = min(cashLimit, positionLimit)
            if maxSpendCents <= 0 {
                return .reject(reason: "no allocatable cash")
            }
            let requestedSpend = Int64((order.qty * lastPrice * 100.0).rounded())
            let allowedSpend = min(requestedSpend, maxSpendCents)
            let qty = (Double(allowedSpend) / 100.0) / lastPrice
            if qty <= 0 {
                return .reject(reason: "size would round to zero")
            }
            return .approve(qtyBaseUnits: qty)
        case .sell:
            let held = portfolio.position(for: order.symbol)?.qty ?? 0
            if held <= 0 { return .reject(reason: "no position to sell") }
            return .approve(qtyBaseUnits: min(order.qty, held))
        }
    }

    public func trip(_ reason: String) {
        if !tripped {
            tripped = true
            tripReason = reason
        }
    }

    public func reset() {
        tripped = false; tripReason = nil
        peakEquityCents = 0; sessionStartCents = 0
    }
}
