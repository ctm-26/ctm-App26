import SwiftUI
import Charts
import TreasuryKernel
import TreasuryTrading

public enum EquityVisual: String, CaseIterable, Hashable {
    case equity = "Equity"
    case drawdown = "Drawdown"
    case both = "Both"
}

public struct EquityCurveChart: View {
    public let curve: [EquityPoint]
    @Binding public var visual: EquityVisual
    @State private var measuredWidth: CGFloat = 0

    public init(curve: [EquityPoint], visual: Binding<EquityVisual>) {
        self.curve = curve; self._visual = visual
    }

    private var drawdown: [(Date, Double)] {
        var peak: Int64 = 0; var out: [(Date, Double)] = []
        for p in curve {
            peak = max(peak, p.equity.cents)
            let dd = peak > 0 ? (Double(p.equity.cents) - Double(peak)) / Double(peak) : 0
            out.append((p.time, dd * 100))
        }
        return out
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Equity curve").font(.headline)
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
        if curve.isEmpty {
            ContentUnavailableView("Run a backtest",
                                   systemImage: "chart.line.uptrend.xyaxis",
                                   description: Text("Pick a strategy and a date range to populate this."))
        } else {
            Chart {
                if visual == .equity || visual == .both {
                    ForEach(curve, id: \.time) { p in
                        LineMark(
                            x: .value("t", p.time),
                            y: .value("equity", p.equity.doubleValue)
                        )
                        .foregroundStyle(Theme.strategyColor)
                        .interpolationMethod(.monotone)
                    }
                }
                if visual == .drawdown || visual == .both {
                    ForEach(drawdown, id: \.0) { (t, dd) in
                        AreaMark(
                            x: .value("t", t),
                            y: .value("dd", dd)
                        )
                        .foregroundStyle(Theme.spendingColor.opacity(0.3))
                        .interpolationMethod(.monotone)
                    }
                }
            }
        }
    }
}
