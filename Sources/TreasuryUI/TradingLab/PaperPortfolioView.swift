import SwiftUI
import TreasuryKernel
import TreasuryTrading

#if canImport(UIKit)

public struct PaperPortfolioView: View {
    @Environment(AppState.self) private var state

    @State private var portfolios: [PortfolioStore.PortfolioRow] = []
    @State private var selectedId: Int64?
    @State private var newName: String = ""
    @State private var newCash: Double = 10_000
    @State private var equity: [EquityPoint] = []
    @State private var equityVisual: EquityVisual = .equity
    @State private var trades: [PortfolioStore.TradeRow] = []

    @State private var strategyIdx: Int = 0
    @State private var symbol: String = "BTC-USD"
    @State private var granularity: Granularity = .hour
    @State private var engineStatus: TradingEngine.Status = .idle
    @State private var engineStartTrigger: Int = 0
    @State private var engineStopTrigger: Int = 0

    private let strategies = StrategyCatalog.all()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if portfolios.isEmpty {
                    createCard
                } else {
                    portfolioPicker
                    if selectedId != nil {
                        engineControls
                        Card { EquityCurveChart(curve: equity, visual: $equityVisual) }
                        Card { tradeFeed }
                    }
                }
            }
            .padding(24)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: engineStartTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: engineStopTrigger)
        .task { reloadPortfolios() }
    }

    private var createCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Create a paper portfolio").font(.headline)
                Text("Live prices feed paper fills. No exchange API keys; no real orders. "
                     + "Every trade is logged to the audit trail.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                    Stepper("Cash: $\(Int(newCash))",
                            value: $newCash, in: 100...1_000_000, step: 500)
                    Spacer()
                    Button("Create") {
                        let name = newName, cents = Int64(newCash * 100)
                        state.task({
                            try await state.portfolios.createPortfolio(
                                name: name, initialCashCents: cents)
                        }) { row in
                            newName = ""
                            reloadPortfolios()
                            selectedId = row.id
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var portfolioPicker: some View {
        Card {
            HStack {
                Picker("Portfolio", selection: $selectedId) {
                    Text("Choose").tag(nil as Int64?)
                    ForEach(portfolios) { p in
                        Text("\(p.name)  ·  \(Money(cents: p.cashCents).formatted())")
                            .tag(Optional(p.id))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedId) { _, _ in reloadSelected() }
                Spacer()
                if let id = selectedId {
                    Button {
                        Task { await stopEngine() }
                    } label: { Label("Stop", systemImage: "stop.fill") }
                        .disabled(engineStatus != .running)
                    Button {
                        Task { await startEngine(portfolioId: id) }
                    } label: { Label("Start", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(engineStatus == .running)
                }
            }
        }
    }

    private var engineControls: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Engine").font(.headline)
                HStack(spacing: 16) {
                    Picker("Strategy", selection: $strategyIdx) {
                        ForEach(strategies.indices, id: \.self) { i in
                            Text(strategies[i].summary).tag(i)
                        }
                    }
                    TextField("Symbol", text: $symbol).frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                    Picker("Granularity", selection: $granularity) {
                        ForEach(Granularity.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 280)
                }
                statusBadge
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch engineStatus {
        case .idle:
            Label("Idle", systemImage: "circle").foregroundStyle(.secondary)
        case .running:
            Label("Running — paper fills only", systemImage: "circle.fill")
                .foregroundStyle(Theme.incomeColor)
        case .stopped(let reason):
            Label("Stopped: \(reason)", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var tradeFeed: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent trades").font(.headline)
            if trades.isEmpty {
                Text("No trades yet").foregroundStyle(.secondary)
            } else {
                ForEach(trades) { t in
                    HStack {
                        Image(systemName: t.side == "buy" ? "arrow.up.right" : "arrow.down.right")
                            .foregroundStyle(t.side == "buy" ? Theme.incomeColor : Theme.spendingColor)
                        Text(t.side.uppercased()).bold()
                        Text(t.symbol)
                        Text(String(format: "%.6f", t.qty)).foregroundStyle(.secondary).monospacedDigit()
                        Text("@ \(Money(cents: t.priceCents).formatted())").monospacedDigit()
                        Spacer()
                        Text(t.strategy).foregroundStyle(Theme.strategyColor).font(.caption)
                        Text(t.executedAt).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func reloadPortfolios() {
        state.task({ try await state.portfolios.portfolios() }) { rows in
            self.portfolios = rows
            if selectedId == nil { selectedId = rows.first?.id }
            reloadSelected()
        }
    }

    private func reloadSelected() {
        guard let id = selectedId else { return }
        state.task({ try await state.portfolios.equitySeries(portfolioId: id) }) { self.equity = $0 }
        state.task({ try await state.portfolios.recentTrades(portfolioId: id) }) { self.trades = $0 }
    }

    private func startEngine(portfolioId: Int64) async {
        let portfolio = portfolios.first { $0.id == portfolioId }
        let broker = PaperBroker(initialCashCents: portfolio?.cashCents ?? 0)
        let governor = RiskGovernor(config: .balanced)
        let engine = TradingEngine(
            db: state.db,
            portfolioId: portfolioId,
            feed: state.feed,
            strategy: strategies[strategyIdx],
            broker: broker,
            governor: governor,
            config: .init(symbol: symbol, granularity: granularity))
        state.engine = engine
        await engine.start()
        await refreshEngineStatus()
        engineStartTrigger &+= 1
    }

    private func stopEngine() async {
        if let engine = state.engine {
            await engine.stop(reason: "manual stop")
        }
        await refreshEngineStatus()
        engineStopTrigger &+= 1
    }

    /// Pull the real status from the actor so the UI mirrors engine state
    /// instead of guessing. Called after start/stop as a one-shot — no polling.
    private func refreshEngineStatus() async {
        if let status = await state.engine?.currentStatus() {
            engineStatus = status
        } else {
            engineStatus = .idle
        }
    }
}

#endif
