import SwiftUI
import TreasuryKernel

#if canImport(UIKit)

public enum DashboardLens: String, CaseIterable, Hashable {
    case spend = "Spend"
    case timeline = "Timeline"
    case cashflow = "Cashflow"
}

public struct DashboardView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var month: String = currentMonth()
    @State private var report: MonthlyReport?
    @State private var dailyPoints: [ReportService.DailyPoint] = []
    @State private var monthly: [ReportService.MonthlyTotal] = []
    @State private var loading: Bool = true

    @State private var lens: DashboardLens = .spend
    @State private var spendVisual: SpendVisual = .donut
    @State private var timelineVisual: TimelineVisual = .area

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                summaryCards
                Card {
                    ChartModeSwitcher(selection: $lens) { $0.rawValue }
                        .padding(.bottom, 6)
                    Divider()
                    Group {
                        switch lens {
                        case .spend:
                            SpendByCategoryChart(rollups: report?.byCategory ?? [],
                                                 visual: $spendVisual)
                        case .timeline:
                            NetWorthTimelineChart(points: dailyPoints, visual: $timelineVisual)
                        case .cashflow:
                            CashflowWaterfallChart(months: monthly)
                        }
                    }
                    .padding(.top, 12)
                }
                accountTable
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(24)
        }
        .overlay {
            if loading && report == nil {
                ProgressView("Loading dashboard…")
                    .padding(20)
                    .background(.regularMaterial,
                                in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { reload() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(loading)
            }
        }
        .task { reload() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text("OUTPUT MIRROR")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(month).font(.largeTitle.bold())
            }
            Spacer()
            MonthStepper(month: $month) { reload() }
        }
    }

    @ViewBuilder
    private var summaryCards: some View {
        let income = report?.income ?? .zero
        let spend = report?.spending ?? .zero
        let net = report?.net ?? .zero
        let netTint: Color = net.cents >= 0 ? Theme.incomeColor : Theme.spendingColor
        let txCount = report?.transactionCount ?? 0

        if hSizeClass == .compact {
            // 2x2 grid on compact width (e.g. portrait iPhone / Slide Over iPad).
            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    metricCard("Income", income.formatted(), Theme.incomeColor)
                    metricCard("Spending", spend.formatted(), Theme.spendingColor)
                }
                GridRow {
                    metricCard("Net", net.formatted(), netTint)
                    metricCard("Transactions", "\(txCount)", Theme.neutralColor)
                }
            }
        } else {
            HStack(spacing: 16) {
                metricCard("Income", income.formatted(), Theme.incomeColor)
                metricCard("Spending", spend.formatted(), Theme.spendingColor)
                metricCard("Net", net.formatted(), netTint)
                metricCard("Transactions", "\(txCount)", Theme.neutralColor)
            }
        }
    }

    private func metricCard(_ label: String, _ value: String, _ tint: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var accountTable: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("By account").font(.headline)
                if let rows = report?.byAccount, !rows.isEmpty {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24,
                         verticalSpacing: 6) {
                        ForEach(rows) { r in
                            GridRow {
                                Text(r.name).bold()
                                Text(r.net.formatted())
                                    .foregroundStyle(r.net.cents >= 0
                                                     ? Theme.incomeColor : Theme.spendingColor)
                                    .monospacedDigit()
                                Text("\(r.count) tx").foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("No transactions in this month").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reload() {
        loading = true
        let m = month
        Task { @MainActor in
            do {
                let r = try await state.reports.monthly(m)
                let d = try await state.reports.dailyCumulative(months: 12)
                let mt = try await state.reports.months(last: 6)
                self.report = r; self.dailyPoints = d; self.monthly = mt
            } catch {
                state.lastError = "\(error)"
            }
            self.loading = false
        }
    }

    private static func currentMonth() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }
}

private struct MonthStepper: View {
    @Binding var month: String
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            TextField("YYYY-MM", text: $month)
                .frame(width: 100)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onChange() }
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
        }
    }

    private func shift(_ delta: Int) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        guard let date = f.date(from: month),
              let next = Calendar.current.date(byAdding: .month, value: delta, to: date)
        else { return }
        month = f.string(from: next); onChange()
    }
}

#endif
