import SwiftUI
import Charts
import TreasuryTrading

public enum PriceVisual: String, CaseIterable, Hashable {
    case candles = "Candles"
    case line = "Line"
    case area = "Area"
}

public struct PriceChart: View {
    public let candles: [Candle]
    @Binding public var visual: PriceVisual
    public let overlays: [(label: String, points: [(Date, Double)], color: Color)]

    public init(candles: [Candle], visual: Binding<PriceVisual>,
                overlays: [(label: String, points: [(Date, Double)], color: Color)] = []) {
        self.candles = candles; self._visual = visual; self.overlays = overlays
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Price").font(.headline)
                Spacer()
                ChartModeSwitcher(selection: $visual) { $0.rawValue }
            }
            chart.frame(height: Theme.chartHeight)
                .animation(.snappy, value: visual)
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
            }
        }
    }
}
