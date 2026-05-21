import SwiftUI
import Charts
import TreasuryKernel

public enum TimelineVisual: String, CaseIterable, Hashable {
    case area = "Area"
    case line = "Line"
}

public struct NetWorthTimelineChart: View {
    public let points: [ReportService.DailyPoint]
    @Binding public var visual: TimelineVisual

    public init(points: [ReportService.DailyPoint], visual: Binding<TimelineVisual>) {
        self.points = points; self._visual = visual
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Net cashflow — running total")
                    .font(.headline)
                Spacer()
                ChartModeSwitcher(selection: $visual) { $0.rawValue }
            }
            chart
                .frame(height: Theme.chartHeight)
                .animation(.snappy, value: visual)
        }
    }

    @ViewBuilder
    private var chart: some View {
        if points.isEmpty {
            ContentUnavailableView("No history yet",
                                   systemImage: "chart.line.uptrend.xyaxis",
                                   description: Text("Import some transactions to populate the timeline."))
        } else {
            Chart(points) { p in
                switch visual {
                case .area:
                    AreaMark(
                        x: .value("date", p.date),
                        y: .value("net", p.net.doubleValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.incomeColor.opacity(0.6), Theme.incomeColor.opacity(0.05)],
                                       startPoint: .top, endPoint: .bottom))
                case .line:
                    LineMark(
                        x: .value("date", p.date),
                        y: .value("net", p.net.doubleValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.incomeColor)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine(); AxisTick(); AxisValueLabel()
                }
            }
        }
    }
}
