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
        /// Approved size in base units. `note` carries advisory metadata
        /// (e.g. "clamped from <requested> to <held>") that callers should
        /// thread into the audit log when present.
        case approve(qtyBaseUnits: Double, note: String?)
        case reject(reason: String)
    }

    public let config: Config
    /// Fee rate the broker will apply, used to reserve fees in spend
    /// approval so we don't approve an order the broker will then reject for
    /// insufficient cash. Should match `PaperBroker.feeRate`.
    public let feeRate: Double
    public private(set) var tripped: Bool = false
    public private(set) var tripReason: String? = nil
    public private(set) var peakEquityCents: Int64 = 0
    // NOTE: `sessionStartCents` is set on the first `updateEquity` call and
    // resets to 0 on `reset()` or whenever the engine restarts (the value
    // lives only in memory). This silently re-baselines the daily-loss
    // limit. Schema migration is out of scope for this PR.
    // TODO(v0.2.2): persist `sessionStartCents` (and peak/tripped) in the
    // ledger DB so daily limits survive an app restart.
    public private(set) var sessionStartCents: Int64 = 0

    public init(config: Config, feeRate: Double = 0.0040) {
        self.config = config
        self.feeRate = feeRate
    }

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
            // Reserve fees in the approval so the broker doesn't reject a
            // size we just approved. `1 + feeRate` covers the worst case
            // where the broker computes fees on full notional.
            let requestedSpend = Int64((order.qty * lastPrice * (1 + feeRate) * 100.0).rounded())
            // Hard reject if the strategy asked to spend more cash than we
            // physically have (after the fee reserve). This is distinct from
            // clamping due to the per-position cap: the position cap will
            // clamp silently, but a bald cash overage rejects outright so
            // strategies can't mask sizing bugs as "small fills".
            if requestedSpend > cashLimit {
                return .reject(reason: "fee-inclusive spend exceeds cash")
            }
            let allowedSpend = min(requestedSpend, maxSpendCents)
            // Back out the fee reserve to get the deployable notional, then
            // convert to base units.
            let deployableCents = Double(allowedSpend) / (1 + feeRate)
            let qty = (deployableCents / 100.0) / lastPrice
            if qty <= 0 {
                return .reject(reason: "size would round to zero")
            }
            let note = allowedSpend < requestedSpend
                ? "clamped from \(order.qty) to \(qty)"
                : nil
            return .approve(qtyBaseUnits: qty, note: note)
        case .sell:
            let held = portfolio.position(for: order.symbol)?.qty ?? 0
            if held <= 0 { return .reject(reason: "no position to sell") }
            let approved = min(order.qty, held)
            let note = approved < order.qty
                ? "clamped from \(order.qty) to \(held)"
                : nil
            return .approve(qtyBaseUnits: approved, note: note)
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
