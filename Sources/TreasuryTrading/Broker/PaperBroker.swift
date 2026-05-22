import Foundation
import TreasuryKernel

/// Paper-trading broker. Holds cash + positions in memory; can persist a
/// snapshot to the ledger DB.
public final class PaperBroker: @unchecked Sendable {
    public struct Snapshot: Sendable {
        public let cashCents: Int64
        public let equityCents: Int64
        public let positions: [Position]
        public var openPositions: Int { positions.filter { $0.qty > 0 }.count }
        public func position(for symbol: String) -> Position? {
            positions.first { $0.symbol == symbol }
        }
    }

    public private(set) var cashCents: Int64
    /// Fee model: percentage of notional. 0.005 = 50 bps (Coinbase-ish).
    public let feeRate: Double
    private var positions: [String: Position] = [:]
    private(set) public var fills: [PaperFill] = []
    private var lastPrices: [String: Double] = [:]

    public init(initialCashCents: Int64, feeRate: Double = 0.0040) {
        self.cashCents = initialCashCents
        self.feeRate = feeRate
    }

    public func updateMark(symbol: String, price: Double) {
        lastPrices[symbol] = price
        if var p = positions[symbol] {
            p.marketPrice = price
            positions[symbol] = p
        }
    }

    public func snapshot(at time: Date = Date()) -> Snapshot {
        var equity = cashCents
        for (sym, var p) in positions {
            if let price = lastPrices[sym] {
                p.marketPrice = price
                equity += Int64((p.qty * price * 100.0).rounded())
                positions[sym] = p
            }
        }
        return Snapshot(cashCents: cashCents, equityCents: equity,
                        positions: Array(positions.values))
    }

    /// Outcome of an order execution. `.rejected` carries a human-readable
    /// reason so the audit log and UI can distinguish "no market price" from
    /// "insufficient cash" from "no position", etc.
    public enum ExecuteOutcome: Sendable {
        case filled(PaperFill)
        case rejected(reason: String)
    }

    /// Execute a sized order against the broker's marked price.
    /// Returns `.filled(PaperFill)` on success or `.rejected(reason:)` if the
    /// order can't be filled.
    @discardableResult
    public func execute(order: Order, qtyBaseUnits: Double, at time: Date = Date()) -> ExecuteOutcome {
        guard let price = lastPrices[order.symbol], price > 0 else {
            return .rejected(reason: "no market price")
        }
        let notional = qtyBaseUnits * price
        let feeCents = Int64((notional * feeRate * 100.0).rounded())
        let notionalCents = Int64((notional * 100.0).rounded())

        let filledQty: Double
        switch order.side {
        case .buy:
            let totalCost = notionalCents + feeCents
            guard cashCents >= totalCost else {
                return .rejected(reason: "insufficient cash")
            }
            cashCents -= totalCost
            var p = positions[order.symbol]
                ?? Position(symbol: order.symbol, qty: 0, avgCostCents: 0, marketPrice: price)
            let prevValue = p.qty * (Double(p.avgCostCents) / 100.0)
            let newQty = p.qty + qtyBaseUnits
            // Convention: average-cost includes fees, so a sell at break-even
            // price after fees registers as a loss (which it economically is).
            let newValue = prevValue + notional + Double(feeCents) / 100.0
            p.qty = newQty
            p.avgCostCents = newQty > 0 ? Int64((newValue / newQty * 100.0).rounded()) : 0
            p.marketPrice = price
            positions[order.symbol] = p
            filledQty = qtyBaseUnits
        case .sell:
            var p = positions[order.symbol]
                ?? Position(symbol: order.symbol, qty: 0, avgCostCents: 0, marketPrice: price)
            let qty = min(qtyBaseUnits, p.qty)
            guard qty > 0 else {
                return .rejected(reason: "no position to sell")
            }
            let proceeds = Int64((qty * price * 100.0).rounded()) - feeCents
            cashCents += proceeds
            p.qty -= qty
            p.marketPrice = price
            positions[order.symbol] = p
            filledQty = qty
        }

        let fill = PaperFill(
            id: order.id,
            order: order,
            priceCents: Int64((price * 100.0).rounded()),
            feeCents: feeCents,
            filledQty: filledQty,
            executedAt: time)
        fills.append(fill)
        return .filled(fill)
    }
}
