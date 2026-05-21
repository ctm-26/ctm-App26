import SwiftUI
import TreasuryKernel

public struct AuditView: View {
    @Environment(AppState.self) private var state
    @State private var events: [AuditEvent] = []

    public init() {}

    public var body: some View {
        List(events) { e in
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
        .navigationTitle("Audit Trail")
        .task { reload() }
        .refreshable { reload() }
    }

    private func reload() {
        state.task({ try await state.audit.recent(limit: 500) }) { self.events = $0 }
    }
}
