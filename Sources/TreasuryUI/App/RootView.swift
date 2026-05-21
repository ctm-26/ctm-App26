import SwiftUI
import TreasuryKernel

public enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, accounts, transactions, rules, reports, tradingLab, audit
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .accounts: return "Accounts"
        case .transactions: return "Transactions"
        case .rules: return "Rules"
        case .reports: return "Reports"
        case .tradingLab: return "Trading Lab"
        case .audit: return "Audit"
        }
    }

    public var systemImage: String {
        switch self {
        case .dashboard: return "rectangle.3.group.fill"
        case .accounts: return "building.columns"
        case .transactions: return "list.bullet.rectangle"
        case .rules: return "wand.and.rays"
        case .reports: return "doc.text.magnifyingglass"
        case .tradingLab: return "chart.line.uptrend.xyaxis"
        case .audit: return "clock.arrow.circlepath"
        }
    }

    public var diagramBox: String {
        switch self {
        case .dashboard: return "OUTPUT MIRROR"
        case .accounts, .transactions: return "LEDGER CORE"
        case .rules: return "RULE ENGINE"
        case .reports: return "OUTPUT MIRROR"
        case .tradingLab: return "FUTURE LAB (paper only)"
        case .audit: return "AUDIT TRAIL"
        }
    }
}

public struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var selection: SidebarSection? = .dashboard

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .alert("Treasury Kernel",
               isPresented: Binding(get: { state.lastError != nil },
                                    set: { if !$0 { state.lastError = nil } })) {
            Button("OK") { state.lastError = nil }
        } message: {
            Text(state.lastError ?? "")
        }
    }

    private var sidebar: some View {
        List(SidebarSection.allCases, selection: $selection) { section in
            NavigationLink(value: section) {
                Label(section.title, systemImage: section.systemImage)
            }
        }
        .navigationTitle("Treasury Kernel")
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .dashboard {
        case .dashboard:    DashboardView()
        case .accounts:     AccountsView()
        case .transactions: TransactionsView()
        case .rules:        RulesView()
        case .reports:      ReportsView()
        case .tradingLab:   TradingLabView()
        case .audit:        AuditView()
        }
    }
}
