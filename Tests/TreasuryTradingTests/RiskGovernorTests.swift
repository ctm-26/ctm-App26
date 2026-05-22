import XCTest
@testable import TreasuryTrading
import TreasuryKernel

final class RiskGovernorTests: XCTestCase {

    private func snapshot(cash: Int64, equity: Int64? = nil,
                         positions: [Position] = []) -> PaperBroker.Snapshot
    {
        PaperBroker.Snapshot(
            cashCents: cash,
            equityCents: equity ?? cash,
            positions: positions)
    }

    // D2(a): approval rejects when fee reservation pushes spend above cash.
    func testRejectsWhenFeeReservationExceedsCash() {
        // Generous limits so only the cash overage rejects the order.
        let g = RiskGovernor(
            config: .init(maxPositionPctEquity: 1.0, maxOpenPositions: 5,
                          maxDrawdownPct: 0.99, dailyLossLimitCents: 0,
                          minCashReserveCents: 0),
            feeRate: 0.0040)
        // Cash $100.00 = 10_000c. Order asks for qty s.t. notional == cash,
        // so notional+fee > cash and the governor should reject.
        // qty * 100 * (1 + 0.004) * 100 > 10_000  ⇒ qty > 0.996...
        // We pick qty = 1.0 → fee-inclusive spend = 1.0 * 100 * 1.004 * 100 = 10_040c.
        let snap = snapshot(cash: 10_000)
        let order = Order(symbol: "TEST", side: .buy, qty: 1.0)
        let d = g.evaluate(order: order, lastPrice: 100.0, portfolio: snap)
        if case .reject(let reason) = d {
            XCTAssertTrue(reason.contains("fee") || reason.contains("cash"),
                          "rejection reason should mention fees/cash, got: \(reason)")
        } else {
            XCTFail("expected reject for fee-inclusive spend over cash, got \(d)")
        }
    }

    // D2(b): a sell order whose qty exceeds the held qty is approved with a
    // non-nil `note` describing the clamp.
    func testApproveSellCarriesClampNote() {
        let g = RiskGovernor(config: .balanced)
        // Hold 0.5 units; ask to sell 1.0.
        let pos = Position(symbol: "TEST", qty: 0.5,
                           avgCostCents: 10_000, marketPrice: 100.0)
        let snap = snapshot(cash: 100_000, equity: 105_000, positions: [pos])
        let order = Order(symbol: "TEST", side: .sell, qty: 1.0)
        let d = g.evaluate(order: order, lastPrice: 100.0, portfolio: snap)
        guard case .approve(let qty, let note) = d else {
            XCTFail("expected approve, got \(d)"); return
        }
        XCTAssertEqual(qty, 0.5, accuracy: 1e-9, "should clamp to held qty")
        XCTAssertNotNil(note, "clamped sell should carry an explanatory note")
        XCTAssertTrue(note?.contains("clamped") ?? false,
                      "note should describe the clamp, got: \(note ?? "nil")")
    }

    // D2(c): once tripped, every subsequent evaluate returns .reject —
    // including ones that would otherwise be valid.
    func testTrippedGovernorRejectsAllSubsequentEvals() {
        let g = RiskGovernor(config: .init(
            maxPositionPctEquity: 0.5, maxOpenPositions: 5,
            maxDrawdownPct: 0.10, dailyLossLimitCents: 0,
            minCashReserveCents: 0))
        g.updateEquity(100_000)
        g.updateEquity(110_000)
        g.updateEquity(80_000) // ~27% drawdown -> trip
        XCTAssertTrue(g.tripped)

        // Even a perfectly sized buy should now reject.
        let snap = snapshot(cash: 100_000)
        let buy = Order(symbol: "TEST", side: .buy, qty: 0.01)
        if case .reject(let r) = g.evaluate(order: buy, lastPrice: 100, portfolio: snap) {
            XCTAssertTrue(r.contains("tripped"), "reject should cite trip state")
        } else { XCTFail("expected reject post-trip on buy") }

        // And a sell of a held position should also reject.
        let pos = Position(symbol: "TEST", qty: 1.0,
                           avgCostCents: 10_000, marketPrice: 100.0)
        let snap2 = snapshot(cash: 100_000, equity: 110_000, positions: [pos])
        let sell = Order(symbol: "TEST", side: .sell, qty: 0.5)
        if case .reject = g.evaluate(order: sell, lastPrice: 100, portfolio: snap2) {
            // expected
        } else { XCTFail("expected reject post-trip on sell") }
    }
}
