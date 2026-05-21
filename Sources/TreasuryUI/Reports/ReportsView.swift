import SwiftUI
import TreasuryKernel

public struct ReportsView: View {
    @Environment(AppState.self) private var state
    @State private var month: String = currentMonth()
    @State private var report: MonthlyReport?
    @State private var spendVisual: SpendVisual = .bars

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let r = report {
                    summary(r)
                    Card {
                        SpendByCategoryChart(rollups: r.byCategory, visual: $spendVisual)
                    }
                    accountBreakdown(r)
                } else {
                    ProgressView().padding()
                }
            }
            .padding(24)
        }
        .navigationTitle("Reports")
        .task { reload() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("MONTHLY REPORT").font(.caption2).foregroundStyle(.secondary)
                Text(month).font(.largeTitle.bold())
            }
            Spacer()
            TextField("YYYY-MM", text: $month)
                .frame(width: 120).textFieldStyle(.roundedBorder)
                .onSubmit { reload() }
        }
    }

    private func summary(_ r: MonthlyReport) -> some View {
        HStack(spacing: 16) {
            metricCard("Income", r.income.formatted(), Theme.incomeColor)
            metricCard("Spending", r.spending.formatted(), Theme.spendingColor)
            metricCard("Net", r.net.formatted(),
                       r.net.cents >= 0 ? Theme.incomeColor : Theme.spendingColor)
            metricCard("Tx", "\(r.transactionCount)", Theme.neutralColor)
        }
    }

    private func accountBreakdown(_ r: MonthlyReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("By account").font(.headline)
                ForEach(r.byAccount) { row in
                    HStack {
                        Text(row.name).bold()
                        Spacer()
                        Text(row.net.formatted())
                            .monospacedDigit()
                            .foregroundStyle(row.net.cents >= 0 ?
                                             Theme.incomeColor : Theme.spendingColor)
                        Text("\(row.count) tx")
                            .foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func metricCard(_ label: String, _ value: String, _ tint: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title2.weight(.semibold)).foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reload() {
        let m = month
        state.task({ try await state.reports.monthly(m) }) { self.report = $0 }
    }

    private static func currentMonth() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }
}
