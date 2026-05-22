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
    @State private var measuredWidth: CGFloat = 0
    @State private var selectedX: Date?

    public init(points: [ReportService.DailyPoint], visual: Binding<TimelineVisual>) {
        self.points = points; self._visual = visual
    }

    /// `DailyPoint.date` is a `YYYY-MM-DD` string; parsed lazily for the
    /// chart's X axis and for nearest-point lookup during scrubbing.
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private struct Sample: Identifiable {
        let id: String
        let date: Date
        let net: Double
        let money: Money
    }

    private var samples: [Sample] {
        points.compactMap { p in
            guard let d = NetWorthTimelineChart.dayParser.date(from: p.date) else { return nil }
            return Sample(id: p.date, date: d, net: p.net.doubleValue, money: p.net)
        }
    }

    private func nearest(_ x: Date) -> Sample? {
        let s = samples
        guard let first = s.first, let last = s.last else { return nil }
        if x < first.date || x > last.date { return nil }
        return s.min(by: { abs($0.date.timeIntervalSince(x)) < abs($1.date.timeIntervalSince(x)) })
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
        if points.isEmpty {
            ContentUnavailableView("No history yet",
                                   systemImage: "chart.line.uptrend.xyaxis",
                                   description: Text("Import some transactions to populate the timeline."))
        } else {
            let rows = samples
            Chart {
                ForEach(rows) { p in
                    switch visual {
                    case .area:
                        AreaMark(
                            x: .value("date", p.date),
                            y: .value("net", p.net)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.incomeColor.opacity(0.6), Theme.incomeColor.opacity(0.05)],
                                           startPoint: .top, endPoint: .bottom))
                    case .line:
                        LineMark(
                            x: .value("date", p.date),
                            y: .value("net", p.net)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.incomeColor)
                    }
                }

                if let x = selectedX, let hit = nearest(x) {
                    RuleMark(x: .value("sel", hit.date))
                        .foregroundStyle(.secondary.opacity(0.5))
                    PointMark(
                        x: .value("sel", hit.date),
                        y: .value("net", hit.net)
                    )
                    .foregroundStyle(Theme.incomeColor)
                    .annotation(position: .top, alignment: .center, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.date, format: .dateTime.year().month().day())
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(hit.money.formatted())
                                .font(.caption).bold()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine(); AxisTick(); AxisValueLabel()
                }
            }
            .chartXSelection(value: $selectedX)
            .accessibilityChartDescriptor(self)
        }
    }
}

extension NetWorthTimelineChart: AXChartDescriptorRepresentable {
    public func makeChartDescriptor() -> AXChartDescriptor {
        let rows = samples
        let dates = rows.map(\.date)
        let nets = rows.map(\.net)

        let minDate = dates.min() ?? Date()
        let maxDate = dates.max() ?? Date()
        let minNet = nets.min() ?? 0
        let maxNet = nets.max() ?? 0

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Date",
            range: minDate.timeIntervalSinceReferenceDate ... max(minDate.timeIntervalSinceReferenceDate + 1,
                                                                  maxDate.timeIntervalSinceReferenceDate),
            gridlinePositions: []
        ) { value in
            dateFormatter.string(from: Date(timeIntervalSinceReferenceDate: value))
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Net (USD)",
            range: min(0, minNet) ... max(0, maxNet, minNet + 1),
            gridlinePositions: []
        ) { value in
            Money(cents: Int64(value * 100)).formatted()
        }

        let series = AXDataSeriesDescriptor(
            name: "Net cashflow",
            isContinuous: true,
            dataPoints: rows.map { s in
                AXDataPoint(x: s.date.timeIntervalSinceReferenceDate,
                            y: s.net,
                            label: dateFormatter.string(from: s.date))
            }
        )

        return AXChartDescriptor(
            title: "Net cashflow timeline",
            summary: "Running total of net cashflow across all accounts over time.",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
