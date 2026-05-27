import SwiftUI
import Charts
import TreasuryKernel

#if canImport(UIKit)

public enum SpendVisual: String, CaseIterable, Hashable {
    case donut = "Donut"
    case bars = "Bars"
    case stack = "Stack"
}

public struct SpendByCategoryChart: View {
    public let rollups: [CategoryRollup]
    @Binding public var visual: SpendVisual
    @State private var measuredWidth: CGFloat = 0
    /// Only used by the `.bars` mode — a tapped category gets highlighted while
    /// the rest fade. Donut / stack don't use this.
    @State private var highlighted: String?

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

    private func opacity(for name: String) -> Double {
        guard let h = highlighted else { return 1.0 }
        return h == name ? 1.0 : 0.25
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
                .accessibilityChartDescriptor(self)
            case .bars:
                Chart(spendRows) { row in
                    BarMark(
                        x: .value("amt", row.amount.doubleValue),
                        y: .value("cat", row.name)
                    )
                    .foregroundStyle(by: .value("cat", row.name))
                    .opacity(opacity(for: row.name))
                    .annotation(position: .trailing) {
                        Text(row.amount.formatted())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartLegend(.hidden)
                .accessibilityChartDescriptor(self)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let frame = geo[plotFrame]
                                let local = CGPoint(x: location.x - frame.minX,
                                                    y: location.y - frame.minY)
                                guard local.y >= 0, local.y <= frame.height else { return }
                                if let tapped: String = proxy.value(atY: local.y) {
                                    withAnimation(.snappy) {
                                        highlighted = (highlighted == tapped) ? nil : tapped
                                    }
                                }
                            }
                    }
                }
            case .stack:
                Chart(spendRows) { row in
                    BarMark(
                        x: .value("month", "this month"),
                        y: .value("amt", row.amount.doubleValue)
                    )
                    .foregroundStyle(by: .value("cat", row.name))
                }
                .chartLegend(position: .bottom)
                .accessibilityChartDescriptor(self)
            }
        }
    }
}

extension SpendByCategoryChart: AXChartDescriptorRepresentable {
    public func makeChartDescriptor() -> AXChartDescriptor {
        let rows = spendRows
        let categories = rows.map(\.name)
        let amounts = rows.map { $0.amount.doubleValue }

        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Category",
            categoryOrder: categories
        )

        let maxA = amounts.max() ?? 1
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Amount (USD)",
            range: 0 ... max(maxA, 1),
            gridlinePositions: []
        ) { value in
            Money(cents: Int64(value * 100)).formatted()
        }

        let series = AXDataSeriesDescriptor(
            name: "Spending",
            isContinuous: false,
            dataPoints: rows.map { r in
                AXDataPoint(x: r.name,
                            y: r.amount.doubleValue,
                            label: "\(r.name): \(r.amount.formatted()) across \(r.count) transactions")
            }
        )

        return AXChartDescriptor(
            title: "Spending by category",
            summary: "Total amount spent in each category for the current period.",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

#endif
