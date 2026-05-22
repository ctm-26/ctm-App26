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
    @State private var selectedX: Date?

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

    private func nearestEquity(_ x: Date) -> EquityPoint? {
        guard let first = curve.first, let last = curve.last else { return nil }
        if x < first.time || x > last.time { return nil }
        return curve.min(by: { abs($0.time.timeIntervalSince(x)) < abs($1.time.timeIntervalSince(x)) })
    }

    private func nearestDrawdown(_ x: Date) -> (Date, Double)? {
        let dd = drawdown
        guard let first = dd.first, let last = dd.last else { return nil }
        if x < first.0 || x > last.0 { return nil }
        return dd.min(by: { abs($0.0.timeIntervalSince(x)) < abs($1.0.timeIntervalSince(x)) })
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

                if let x = selectedX {
                    if (visual == .equity || visual == .both), let hit = nearestEquity(x) {
                        RuleMark(x: .value("sel", hit.time))
                            .foregroundStyle(.secondary.opacity(0.5))
                        PointMark(
                            x: .value("sel", hit.time),
                            y: .value("equity", hit.equity.doubleValue)
                        )
                        .foregroundStyle(Theme.strategyColor)
                        .annotation(position: .top, alignment: .center, spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.time, format: .dateTime.year().month().day())
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(hit.equity.formatted())
                                    .font(.caption).bold()
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                        }
                    } else if visual == .drawdown, let hit = nearestDrawdown(x) {
                        RuleMark(x: .value("sel", hit.0))
                            .foregroundStyle(.secondary.opacity(0.5))
                        PointMark(
                            x: .value("sel", hit.0),
                            y: .value("dd", hit.1)
                        )
                        .foregroundStyle(Theme.spendingColor)
                        .annotation(position: .top, alignment: .center, spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.0, format: .dateTime.year().month().day())
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(String(format: "%.2f%%", hit.1))
                                    .font(.caption).bold()
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedX)
            .accessibilityChartDescriptor(self)
        }
    }
}

extension EquityCurveChart: AXChartDescriptorRepresentable {
    public func makeChartDescriptor() -> AXChartDescriptor {
        let times = curve.map(\.time)
        let equities = curve.map { $0.equity.doubleValue }

        let minDate = times.min() ?? Date()
        let maxDate = times.max() ?? Date()
        let minEq = equities.min() ?? 0
        let maxEq = equities.max() ?? 0

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Time",
            range: minDate.timeIntervalSinceReferenceDate ... max(minDate.timeIntervalSinceReferenceDate + 1,
                                                                  maxDate.timeIntervalSinceReferenceDate),
            gridlinePositions: []
        ) { value in
            dateFormatter.string(from: Date(timeIntervalSinceReferenceDate: value))
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Equity (USD)",
            range: min(0, minEq) ... max(maxEq, minEq + 1),
            gridlinePositions: []
        ) { value in
            Money(cents: Int64(value * 100)).formatted()
        }

        let equitySeries = AXDataSeriesDescriptor(
            name: "Equity",
            isContinuous: true,
            dataPoints: curve.map { p in
                AXDataPoint(x: p.time.timeIntervalSinceReferenceDate,
                            y: p.equity.doubleValue,
                            label: dateFormatter.string(from: p.time))
            }
        )

        return AXChartDescriptor(
            title: "Equity curve",
            summary: "Portfolio equity over the backtest or paper-trading window.",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [equitySeries]
        )
    }
}
