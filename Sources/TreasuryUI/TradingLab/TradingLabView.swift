import SwiftUI
import TreasuryKernel
import TreasuryTrading

public enum TradingLens: String, CaseIterable, Hashable {
    case backtest = "Backtest"
    case paper = "Paper"
    case history = "History"
}

public struct TradingLabView: View {
    @Environment(AppState.self) private var state
    @State private var lens: TradingLens = .backtest

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
                .padding(.horizontal, 24).padding(.top, 16)
            Picker("", selection: $lens) {
                ForEach(TradingLens.allCases, id: \.self) { t in Text(t.rawValue).tag(t) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            Divider()
            Group {
                switch lens {
                case .backtest: BacktestView()
                case .paper:    PaperPortfolioView()
                case .history:  TradeHistoryView()
                }
            }
        }
        .navigationTitle("Trading Lab")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FUTURE LAB").font(.caption2).foregroundStyle(.secondary)
                Text("Paper trading sandbox").font(.title2.bold())
                Text("Live prices via Coinbase public API. No exchange keys. No live orders.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "shield.fill")
                .foregroundStyle(Theme.incomeColor)
        }
    }
}
