import SwiftUI
import TreasuryKernel

#if canImport(UIKit)

public struct ReportsView: View {
    @Environment(AppState.self) private var state
    @State private var month: String = currentMonth()
    @State private var report: MonthlyReport?
    @State private var spendVisual: SpendVisual = .bars
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                content
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(24)
        }
        .navigationTitle("Reports")
        .refreshable {
            let m = month
            isLoading = true
            errorMessage = nil
            do {
                self.report = try await state.reports.monthly(m)
            } catch {
                self.errorMessage = "\(error)"
                state.lastError = "\(error)"
            }
            self.isLoading = false
        }
        .task { reload() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && report == nil {
            ProgressView("Loading report…")
                .frame(maxWidth: .infinity, minHeight: 240)
        } else if let message = errorMessage {
            ContentUnavailableView {
                Label("Couldn’t load report", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { reload() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        } else if let r = report {
            if r.transactionCount == 0 {
                ContentUnavailableView("No transactions for \(month)",
                                       systemImage: "tray",
                                       description: Text("Pick another month or import a CSV."))
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                summary(r)
                Card {
                    SpendByCategoryChart(rollups: r.byCategory, visual: $spendVisual)
                }
                accountBreakdown(r)
            }
        } else {
            ProgressView().padding()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("MONTHLY REPORT").font(.caption2).foregroundStyle(.secondary)
                Text(month).font(.largeTitle.bold())
            }
            Spacer()
            TextField("YYYY-MM", text: $month)
                .frame(width: 120).textFieldStyle(.roundedBorder)
                .onSubmit { reload() }
        }
    }

    private func summary(_ r: MonthlyReport) -> some View {
        let code = state.preferredCurrencyCode
        return HStack(spacing: 16) {
            metricCard("Income", r.income.formatted(currencyCode: code), Theme.incomeColor)
            metricCard("Spending", r.spending.formatted(currencyCode: code), Theme.spendingColor)
            metricCard("Net", r.net.formatted(currencyCode: code),
                       r.net.cents >= 0 ? Theme.incomeColor : Theme.spendingColor)
            metricCard("Tx", "\(r.transactionCount)", Theme.neutralColor)
        }
    }

    private func accountBreakdown(_ r: MonthlyReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("By account").font(.headline)
                ForEach(r.byAccount) { row in
                    HStack {
                        Text(row.name).bold()
                        Spacer()
                        Text(row.net.formatted(currencyCode: state.preferredCurrencyCode))
                            .monospacedDigit()
                            .foregroundStyle(row.net.cents >= 0 ?
                                             Theme.incomeColor : Theme.spendingColor)
                        Text("\(row.count) tx")
                            .foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func metricCard(_ label: String, _ value: String, _ tint: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title2.weight(.semibold)).foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reload() {
        let m = month
        isLoading = true
        errorMessage = nil
        Task { @MainActor in
            do {
                self.report = try await state.reports.monthly(m)
            } catch {
                self.errorMessage = "\(error)"
                state.lastError = "\(error)"
            }
            self.isLoading = false
        }
    }

    private static func currentMonth() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }
}

#endif
