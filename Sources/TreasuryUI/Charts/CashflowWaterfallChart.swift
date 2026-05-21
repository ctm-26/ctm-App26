import SwiftUI
import Charts
import TreasuryKernel

public struct CashflowWaterfallChart: View {
    public let months: [ReportService.MonthlyTotal]

    public init(months: [ReportService.MonthlyTotal]) {
        self.months = months
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cashflow — income vs spending by month")
                .font(.headline)
            if months.isEmpty {
                ContentUnavailableView("No monthly data yet",
                                       systemImage: "chart.bar",
                                       description: Text("Import a month or two of statements."))
                    .frame(height: Theme.chartHeight)
            } else {
                Chart {
                    ForEach(months) { m in
                        BarMark(
                            x: .value("month", m.month),
                            y: .value("amt", m.income.doubleValue)
                        )
                        .foregroundStyle(Theme.incomeColor)
                        .annotation(position: .top, alignment: .center) {
                            Text(m.income.formatted())
                                .font(.caption2).foregroundStyle(.secondary)
                        }

                        BarMark(
                            x: .value("month", m.month),
                            y: .value("amt", m.spending.doubleValue)
                        )
                        .foregroundStyle(Theme.spendingColor)

                        RuleMark(y: .value("zero", 0))
                            .foregroundStyle(.secondary.opacity(0.3))
                    }
                }
                .frame(height: Theme.chartHeight)
            }
        }
    }
}
