import SwiftUI
import TreasuryKernel
import TreasuryTrading

#if canImport(UIKit)

/// Lightweight, picker-friendly choice for the risk governor preset.
/// Translated to `RiskGovernor.Config` only at submission time.
private enum GovProfile: String, CaseIterable, Hashable {
    case conservative
    case balanced

    var config: RiskGovernor.Config {
        switch self {
        case .conservative: return .conservative
        case .balanced:     return .balanced
        }
    }

    var displayName: String {
        switch self {
        case .conservative: return "Conservative"
        case .balanced:     return "Balanced"
        }
    }
}

public struct BacktestView: View {
    @Environment(AppState.self) private var state

    @State private var strategyIdx: Int = 0
    @State private var symbol: String = "BTC-USD"
    @State private var granularity: Granularity = .hour
    @State private var lookbackDays: Int = 30
    @State private var initialCashDollars: Double = 10_000
    @State private var govProfile: GovProfile = .balanced
    @State private var equityVisual: EquityVisual = .both
    @State private var priceVisual: PriceVisual = .candles

    @State private var candles: [Candle] = []
    @State private var result: BacktestResult?
    @State private var running = false

    private let strategies = StrategyCatalog.all()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                controls
                if running { ProgressView("Pulling candles…").padding() }
                if let r = result {
                    statsCard(r.stats)
                    Card { EquityCurveChart(curve: r.equityCurve, visual: $equityVisual) }
                    Card {
                        PriceChart(candles: candles, visual: $priceVisual,
                                   overlays: tradeOverlays(r))
                    }
                    Card { tradesList(r.trades) }
                }
            }
            .padding(24)
        }
    }

    private var controls: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Picker("Strategy", selection: $strategyIdx) {
                        ForEach(strategies.indices, id: \.self) { i in
                            Text(strategies[i].summary).tag(i)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Symbol", text: $symbol).frame(width: 120)
                        .textFieldStyle(.roundedBorder)

                    Picker("Granularity", selection: $granularity) {
                        ForEach(Granularity.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }
                HStack(spacing: 16) {
                    Stepper("Lookback: \(lookbackDays) days", value: $lookbackDays, in: 1...365)
                    Stepper("Cash: $\(Int(initialCashDollars))",
                            value: $initialCashDollars, in: 100...1_000_000, step: 500)
                    Picker("Risk", selection: $govProfile) {
                        ForEach(GovProfile.allCases, id: \.self) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }.pickerStyle(.segmented).frame(maxWidth: 280)
                }
                HStack {
                    Spacer()
                    Button {
                        run()
                    } label: { Label("Run backtest", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(running)
                }
            }
        }
    }

    private func statsCard(_ s: BacktestStats) -> some View {
        Card {
            HStack(spacing: 24) {
                stat("Return", String(format: "%+.2f%%", s.totalReturnPct * 100),
                     s.totalReturnPct >= 0 ? Theme.incomeColor : Theme.spendingColor)
                stat("Max DD", String(format: "%.2f%%", s.maxDrawdownPct * 100),
                     Theme.spendingColor)
                stat("Trades", "\(s.tradeCount)", Theme.neutralColor)
                stat("Win rate", String(format: "%.0f%%", s.winRate * 100), Theme.neutralColor)
                stat("Sharpe", String(format: "%.2f", s.sharpe), Theme.neutralColor)
                stat("Final", s.finalEquity.formatted(),
                     s.finalEquity.cents >= s.initialEquity.cents
                     ? Theme.incomeColor : Theme.spendingColor)
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(tint)
                .monospacedDigit()
        }
    }

    private func tradeOverlays(_ r: BacktestResult) -> [(label: String, points: [(Date, Double)], color: Color)] {
        let buys = r.trades.filter { $0.order.side == .buy }
            .map { ($0.executedAt, Double($0.priceCents) / 100.0) }
        let sells = r.trades.filter { $0.order.side == .sell }
            .map { ($0.executedAt, Double($0.priceCents) / 100.0) }
        return [
            ("buys", buys, Theme.incomeColor),
            ("sells", sells, Theme.spendingColor),
        ]
    }

    private func tradesList(_ trades: [PaperFill]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trades").font(.headline)
            if trades.isEmpty {
                Text("No trades for this run").foregroundStyle(.secondary)
            } else {
                ForEach(trades, id: \.id) { t in
                    HStack {
                        Image(systemName: t.order.side == .buy ? "arrow.up.right" : "arrow.down.right")
                            .foregroundStyle(t.order.side == .buy ? Theme.incomeColor : Theme.spendingColor)
                        Text(t.order.side.rawValue.uppercased()).bold()
                        Text(String(format: "%.6f", t.order.qty)).foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text("@ \(Money(cents: t.priceCents).formatted())")
                            .monospacedDigit()
                        Spacer()
                        Text(t.order.reason ?? "").font(.caption).foregroundStyle(.secondary)
                        Text(t.executedAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func run() {
        running = true
        result = nil
        let strategy = strategies[strategyIdx]
        let sym = symbol
        let g = granularity
        let lookback = lookbackDays
        let cash = Int64(initialCashDollars * 100)
        let gov = govProfile.config
        state.task({
            let end = Date()
            let start = end.addingTimeInterval(-TimeInterval(lookback * 86400))
            let cs = try await state.feed.candles(symbol: sym, granularity: g,
                                                  start: start, end: end)
            let bt = Backtester(strategy: strategy, symbol: sym,
                                initialCashCents: cash, governorConfig: gov)
            return (cs, bt.run(candles: cs))
        }) { (cs, r) in
            self.candles = cs
            self.result = r
            self.running = false
        }
    }
}

#endif
