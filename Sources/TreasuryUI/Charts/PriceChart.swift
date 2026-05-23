import SwiftUI
import Charts
import TreasuryKernel
import TreasuryTrading

#if canImport(UIKit)

public enum PriceVisual: String, CaseIterable, Hashable {
    case candles = "Candles"
    case line = "Line"
    case area = "Area"
}

public struct PriceChart: View {
    public let candles: [Candle]
    @Binding public var visual: PriceVisual
    public let overlays: [(label: String, points: [(Date, Double)], color: Color)]
    @State private var measuredWidth: CGFloat = 0
    @State private var selectedX: Date?

    public init(candles: [Candle], visual: Binding<PriceVisual>,
                overlays: [(label: String, points: [(Date, Double)], color: Color)] = []) {
        self.candles = candles; self._visual = visual; self.overlays = overlays
    }

    private func nearest(_ x: Date) -> Candle? {
        guard let first = candles.first, let last = candles.last else { return nil }
        if x < first.time || x > last.time { return nil }
        return candles.min(by: { abs($0.time.timeIntervalSince(x)) < abs($1.time.timeIntervalSince(x)) })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Price").font(.headline)
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
        if candles.isEmpty {
            ContentUnavailableView("No candles loaded",
                                   systemImage: "waveform.path.ecg",
                                   description: Text("Press Refresh to pull market data."))
        } else {
            Chart {
                ForEach(candles, id: \.time) { c in
                    switch visual {
                    case .candles:
                        // Wick
                        RuleMark(
                            x: .value("t", c.time),
                            yStart: .value("low", c.low),
                            yEnd: .value("high", c.high)
                        )
                        .foregroundStyle(c.close >= c.open ? Theme.incomeColor : Theme.spendingColor)
                        // Body
                        BarMark(
                            x: .value("t", c.time),
                            yStart: .value("o", min(c.open, c.close)),
                            yEnd: .value("c", max(c.open, c.close)),
                            width: .fixed(4)
                        )
                        .foregroundStyle(c.close >= c.open ? Theme.incomeColor : Theme.spendingColor)
                    case .line:
                        LineMark(x: .value("t", c.time), y: .value("close", c.close))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.strategyColor)
                    case .area:
                        AreaMark(x: .value("t", c.time), y: .value("close", c.close))
                            .foregroundStyle(
                                LinearGradient(colors: [Theme.strategyColor.opacity(0.5),
                                                        Theme.strategyColor.opacity(0.05)],
                                               startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                }
                ForEach(overlays.indices, id: \.self) { idx in
                    let overlay = overlays[idx]
                    ForEach(overlay.points, id: \.0) { (t, v) in
                        LineMark(
                            x: .value("t", t),
                            y: .value(overlay.label, v),
                            series: .value("series", overlay.label)
                        )
                        .foregroundStyle(overlay.color)
                        .interpolationMethod(.monotone)
                    }
                }

                if let x = selectedX, let hit = nearest(x) {
                    RuleMark(x: .value("sel", hit.time))
                        .foregroundStyle(.secondary.opacity(0.5))
                    PointMark(
                        x: .value("sel", hit.time),
                        y: .value("close", hit.close)
                    )
                    .foregroundStyle(Theme.strategyColor)
                    .annotation(position: .top, alignment: .center, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.time, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(Money(cents: Int64(hit.close * 100)).formatted())
                                .font(.caption).bold()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                    }
                }
            }
            .chartXSelection(value: $selectedX)
            .accessibilityChartDescriptor(self)
        }
    }
}

extension PriceChart: AXChartDescriptorRepresentable {
    public func makeChartDescriptor() -> AXChartDescriptor {
        let times = candles.map(\.time)
        let closes = candles.map(\.close)
        let lows = candles.map(\.low)
        let highs = candles.map(\.high)

        let minDate = times.min() ?? Date()
        let maxDate = times.max() ?? Date()
        let minY = lows.min() ?? 0
        let maxY = highs.max() ?? max(minY + 1, 1)

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Time",
            range: minDate.timeIntervalSinceReferenceDate ... max(minDate.timeIntervalSinceReferenceDate + 1,
                                                                  maxDate.timeIntervalSinceReferenceDate),
            gridlinePositions: []
        ) { value in
            dateFormatter.string(from: Date(timeIntervalSinceReferenceDate: value))
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Price (USD)",
            range: minY ... max(maxY, minY + 1),
            gridlinePositions: []
        ) { value in
            Money(cents: Int64(value * 100)).formatted()
        }

        let series = AXDataSeriesDescriptor(
            name: "Close",
            isContinuous: true,
            dataPoints: zip(times, closes).map { (t, v) in
                AXDataPoint(x: t.timeIntervalSinceReferenceDate,
                            y: v,
                            label: dateFormatter.string(from: t))
            }
        )

        return AXChartDescriptor(
            title: "Price chart",
            summary: "Price over time. Candle bodies show open / close; wicks show the period high and low.",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

#endif
