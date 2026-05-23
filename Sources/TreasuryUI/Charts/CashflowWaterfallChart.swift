import SwiftUI
import Charts
import TreasuryKernel

#if canImport(UIKit)

public struct CashflowWaterfallChart: View {
    public let months: [ReportService.MonthlyTotal]
    @State private var measuredWidth: CGFloat = 0
    @State private var selectedX: String?

    public init(months: [ReportService.MonthlyTotal]) {
        self.months = months
    }

    private var chartHeight: CGFloat {
        Theme.responsiveChartHeight(width: max(measuredWidth, 280))
    }

    private func hit(_ key: String) -> ReportService.MonthlyTotal? {
        months.first(where: { $0.month == key })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cashflow — income vs spending by month")
                .font(.headline)
            Group {
                if months.isEmpty {
                    ContentUnavailableView("No monthly data yet",
                                           systemImage: "chart.bar",
                                           description: Text("Import a month or two of statements."))
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

                        if let key = selectedX, let m = hit(key) {
                            RuleMark(x: .value("sel", m.month))
                                .foregroundStyle(.secondary.opacity(0.5))
                                .annotation(position: .top, alignment: .center, spacing: 6) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.month)
                                            .font(.caption2).foregroundStyle(.secondary)
                                        Text("In \(m.income.formatted())")
                                            .font(.caption)
                                            .foregroundStyle(Theme.incomeColor)
                                        Text("Out \(m.spending.formatted())")
                                            .font(.caption)
                                            .foregroundStyle(Theme.spendingColor)
                                        Text("Net \(m.net.formatted())")
                                            .font(.caption).bold()
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
                        }
                    }
                    .chartXSelection(value: $selectedX)
                    .accessibilityChartDescriptor(self)
                }
            }
            .frame(height: chartHeight)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ChartWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(ChartWidthKey.self) { measuredWidth = $0 }
        }
    }
}

extension CashflowWaterfallChart: AXChartDescriptorRepresentable {
    public func makeChartDescriptor() -> AXChartDescriptor {
        // Categorical X axis (month strings) — use a category descriptor.
        let categories = months.map(\.month)
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Month",
            categoryOrder: categories
        )

        let incomes = months.map { $0.income.doubleValue }
        let spends = months.map { $0.spending.doubleValue }
        let minY = (spends + [0]).min() ?? 0
        let maxY = (incomes + [0]).max() ?? max(minY + 1, 1)

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Amount (USD)",
            range: minY ... max(maxY, minY + 1),
            gridlinePositions: []
        ) { value in
            Money(cents: Int64(value * 100)).formatted()
        }

        let incomeSeries = AXDataSeriesDescriptor(
            name: "Income",
            isContinuous: false,
            dataPoints: months.map { m in
                AXDataPoint(x: m.month,
                            y: m.income.doubleValue,
                            label: "\(m.month) income: \(m.income.formatted())")
            }
        )
        let spendSeries = AXDataSeriesDescriptor(
            name: "Spending",
            isContinuous: false,
            dataPoints: months.map { m in
                AXDataPoint(x: m.month,
                            y: m.spending.doubleValue,
                            label: "\(m.month) spending: \(m.spending.formatted())")
            }
        )

        return AXChartDescriptor(
            title: "Cashflow by month",
            summary: "Monthly income vs spending, color coded; positive bars are income, negative are spending.",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [incomeSeries, spendSeries]
        )
    }
}

#endif
