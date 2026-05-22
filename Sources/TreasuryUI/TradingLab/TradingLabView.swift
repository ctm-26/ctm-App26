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
            paperOnlyBanner
                .padding(.horizontal, 24).padding(.top, 12)
            header
                .padding(.horizontal, 24)
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

    /// Prominent reminder that the Trading Lab can never place real orders.
    /// Yellow/orange tint, shield icon, hard-coded copy.
    private var paperOnlyBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.title3)
                .foregroundStyle(.orange)
            Text("PAPER TRADING — no live orders, no real money.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.6), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Paper trading only. No live orders, no real money.")
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
