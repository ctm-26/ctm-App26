import SwiftUI
import TreasuryKernel
import TreasuryTrading

#if canImport(UIKit)

public struct TradeHistoryView: View {
    @Environment(AppState.self) private var state
    @State private var portfolios: [PortfolioStore.PortfolioRow] = []
    @State private var selectedId: Int64?
    @State private var trades: [PortfolioStore.TradeRow] = []
    @State private var exportTarget: ExportableURL?

    public init() {}

    /// Wrapper so `URL` can be used with `sheet(item:)` which requires Identifiable.
    private struct ExportableURL: Identifiable {
        let id = UUID()
        let url: URL
    }

    public var body: some View {
        VStack(alignment: .leading) {
            if portfolios.isEmpty {
                ContentUnavailableView("No portfolios yet",
                                       systemImage: "tray",
                                       description: Text("Create a paper portfolio in the Paper tab to see trades here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Card {
                    Picker("Portfolio", selection: $selectedId) {
                        Text("All").tag(nil as Int64?)
                        ForEach(portfolios) { p in Text(p.name).tag(Optional(p.id)) }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedId) { _, _ in reload() }
                }
                .padding(.horizontal, 24)
                List(trades) { t in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Image(systemName: t.side == "buy" ? "arrow.up.right" : "arrow.down.right")
                                    .foregroundStyle(t.side == "buy" ? Theme.incomeColor : Theme.spendingColor)
                                Text(t.side.uppercased()).bold()
                                Text(t.symbol)
                            }
                            Text(t.strategy).font(.caption).foregroundStyle(Theme.strategyColor)
                            Text(t.reason).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(Money(cents: t.priceCents).formatted()).monospacedDigit()
                            Text(String(format: "%.6f", t.qty))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            Text(t.executedAt).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { exportCurrentPortfolio() } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(selectedId == nil)
            }
        }
        .sheet(item: $exportTarget) { target in
            NavigationStack {
                ShareLink(item: target.url) {
                    Label("Share \(target.url.lastPathComponent)",
                          systemImage: "square.and.arrow.up")
                }
                .padding()
            }
            .presentationDetents([.medium])
        }
        .task { reloadPortfolios() }
    }

    private func reloadPortfolios() {
        state.task({ try await state.portfolios.portfolios() }) { rows in
            self.portfolios = rows
            self.selectedId = rows.first?.id
            reload()
        }
    }

    private func reload() {
        if let id = selectedId {
            state.task({ try await state.portfolios.recentTrades(portfolioId: id) }) {
                self.trades = $0
            }
        } else {
            trades = []
        }
    }

    private func exportCurrentPortfolio() {
        guard let pid = selectedId else { return }
        state.task({
            try await state.portfolios.exportTradesCSV(portfolioId: pid)
        }) { csv in
            let ts = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("paper-trades-\(pid)-\(ts).csv")
            try? csv.write(to: url, atomically: true, encoding: .utf8)
            self.exportTarget = ExportableURL(url: url)
        }
    }
}

#endif
