import SwiftUI
import TreasuryKernel

#if canImport(UIKit)

public struct AuditView: View {
    @Environment(AppState.self) private var state
    @State private var events: [AuditEvent] = []
    @State private var actions: [String] = []
    @State private var filterAction: String? = nil   // nil = all actions
    @State private var searchText: String = ""
    @State private var loading: Bool = false
    @State private var hasMore: Bool = true

    private static let pageSize: Int = 100

    public init() {}

    public var body: some View {
        Group {
            if loading && events.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !loading && events.isEmpty {
                ContentUnavailableView("No matching audit events",
                                       systemImage: "magnifyingglass",
                                       description: Text("Try clearing the action filter or search."))
            } else {
                List {
                    ForEach(events) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(e.action).font(.body.weight(.medium))
                                Spacer()
                                Text(e.createdAt).font(.caption2).foregroundStyle(.tertiary)
                            }
                            if let d = e.details, !d.isEmpty {
                                Text(d).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    if hasMore {
                        HStack {
                            Spacer()
                            if loading {
                                ProgressView()
                            } else {
                                Button("Load more") { loadMore() }
                                    .buttonStyle(.bordered)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .navigationTitle("Audit Trail")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        filterAction = nil
                        reload()
                    } label: {
                        if filterAction == nil {
                            Label("All actions", systemImage: "checkmark")
                        } else {
                            Text("All actions")
                        }
                    }
                    if !actions.isEmpty {
                        Divider()
                        ForEach(actions, id: \.self) { a in
                            Button {
                                filterAction = a
                                reload()
                            } label: {
                                if filterAction == a {
                                    Label(a, systemImage: "checkmark")
                                } else {
                                    Text(a)
                                }
                            }
                        }
                    }
                } label: {
                    Label(filterAction ?? "All actions", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search details…")
        .onChange(of: searchText) { _, _ in reload() }
        .refreshable { reload() }
        .task {
            reloadActions()
            reload()
        }
    }

    private func reloadActions() {
        state.task({ try await state.audit.actions() }) { self.actions = $0 }
    }

    private func reload() {
        let action = filterAction
        let search = searchText.isEmpty ? nil : searchText
        let pageSize = Self.pageSize
        loading = true
        hasMore = true
        state.task({
            try await state.audit.recent(limit: pageSize,
                                         beforeId: nil,
                                         action: action,
                                         search: search)
        }) { rows in
            self.events = rows
            self.hasMore = rows.count == pageSize
            self.loading = false
        }
    }

    private func loadMore() {
        guard hasMore, !loading else { return }
        guard let cursor = events.last?.id else { return }
        let action = filterAction
        let search = searchText.isEmpty ? nil : searchText
        let pageSize = Self.pageSize
        loading = true
        state.task({
            try await state.audit.recent(limit: pageSize,
                                         beforeId: cursor,
                                         action: action,
                                         search: search)
        }) { rows in
            self.events.append(contentsOf: rows)
            self.hasMore = rows.count == pageSize
            self.loading = false
        }
    }
}

#endif
