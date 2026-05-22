import SwiftUI
import Charts
import TreasuryKernel

public enum SpendVisual: String, CaseIterable, Hashable {
    case donut = "Donut"
    case bars = "Bars"
    case stack = "Stack"
}

public struct SpendByCategoryChart: View {
    public let rollups: [CategoryRollup]
    @Binding public var visual: SpendVisual
    @State private var measuredWidth: CGFloat = 0

    public init(rollups: [CategoryRollup], visual: Binding<SpendVisual>) {
        self.rollups = rollups; self._visual = visual
    }

    /// Only spending categories (negative totals). Income shown separately.
    private var spendRows: [CategoryRollup] {
        rollups
            .filter { $0.amount.cents < 0 }
            .map { CategoryRollup(name: $0.name,
                                  amount: Money(cents: -$0.amount.cents),
                                  count: $0.count) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spending by category").font(.headline)
                Spacer()
                ChartModeSwitcher(selection: $visual) { $0.rawValue }
            }
            chart
                .frame(height: Theme.responsiveChartHeight(width: max(measuredWidth, 280)))
                .animation(.snappy, value: visual)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ChartWidthKey.self, value: geo.size.width)
                    }
                )
                .onPreferenceChange(ChartWidthKey.self) { measuredWidth = $0 }
        }
    }

    @ViewBuilder
    private var chart: some View {
        if spendRows.isEmpty {
            ContentUnavailableView("No spending yet",
                                   systemImage: "chart.pie",
                                   description: Text("Import a CSV to see this fill in."))
        } else {
            switch visual {
            case .donut:
                Chart(spendRows) { row in
                    SectorMark(
                        angle: .value("amt", row.amount.doubleValue),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(by: .value("cat", row.name))
                }
                .chartLegend(position: .bottom, alignment: .center, spacing: 10)
            case .bars:
                Chart(spendRows) { row in
                    BarMark(
                        x: .value("amt", row.amount.doubleValue),
                        y: .value("cat", row.name)
                    )
                    .foregroundStyle(by: .value("cat", row.name))
                    .annotation(position: .trailing) {
                        Text(row.amount.formatted())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartLegend(.hidden)
            case .stack:
                Chart(spendRows) { row in
                    BarMark(
                        x: .value("month", "this month"),
                        y: .value("amt", row.amount.doubleValue)
                    )
                    .foregroundStyle(by: .value("cat", row.name))
                }
                .chartLegend(position: .bottom)
            }
        }
    }
}
