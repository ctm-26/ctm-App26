import SwiftUI
import SwiftData

struct ClaimListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Claim.createdAt, order: .reverse)
    private var allClaims: [Claim]

    @Query private var allEntities: [Entity]

    @State private var searchText: String = ""
    @State private var showAddClaim = false
    @State private var expandedClaimId: String? = nil

    private var filteredClaims: [Claim] {
        if searchText.isEmpty { return allClaims }
        let lower = searchText.lowercased()
        return allClaims.filter { claim in
            if claim.predicate.lowercased().contains(lower) { return true }
            if let subjectEntity = entityById(claim.subjectEntityId),
               subjectEntity.canonicalName.lowercased().contains(lower) { return true }
            if let oid = claim.objectEntityId,
               let objectEntity = entityById(oid),
               objectEntity.canonicalName.lowercased().contains(lower) { return true }
            if let value = claim.value, value.lowercased().contains(lower) { return true }
            return false
        }
    }

    var body: some View {
        Group {
            if allClaims.isEmpty {
                emptyStateView
            } else {
                listContent
            }
        }
        .navigationTitle("Claims")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddClaim = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Claim")
            }
        }
        .sheet(isPresented: $showAddClaim) {
            AddEditClaimView()
        }
    }

    // MARK: - List Content

    private var listContent: some View {
        List {
            ForEach(filteredClaims) { claim in
                ClaimListRow(
                    claim: claim,
                    subjectName: entityById(claim.subjectEntityId)?.canonicalName ?? "Unknown",
                    objectName: objectDisplay(for: claim),
                    isExpanded: expandedClaimId == claim.id,
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedClaimId = expandedClaimId == claim.id ? nil : claim.id
                        }
                    }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteClaim(claim)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        expandedClaimId = claim.id
                    } label: {
                        Label("Details", systemImage: "info.circle")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Filter by predicate or entity")
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("No Claims Yet")
                    .font(.title3.weight(.semibold))
                Text("Claims are facts about entities — relationships, attributes, and behaviors you've recorded.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                showAddClaim = true
            } label: {
                Label("Add Claim", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddClaim) {
            AddEditClaimView()
        }
    }

    // MARK: - Helpers

    private func entityById(_ id: String) -> Entity? {
        allEntities.first { $0.id == id }
    }

    private func objectDisplay(for claim: Claim) -> String {
        if let oid = claim.objectEntityId, let entity = entityById(oid) {
            return entity.canonicalName
        }
        return claim.value ?? "—"
    }

    private func deleteClaim(_ claim: Claim) {
        modelContext.delete(claim)
        try? modelContext.save()
    }
}

// MARK: - Claim List Row

private struct ClaimListRow: View {
    let claim: Claim
    let subjectName: String
    let objectName: String
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: isExpanded ? 10 : 4) {
                // Main triple row
                HStack(spacing: 0) {
                    Text(subjectName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("  ·  ")
                        .foregroundStyle(.tertiary)

                    Text(claim.predicate)
                        .font(.subheadline)
                        .foregroundStyle(.accentColor)
                        .italic()
                        .lineLimit(1)

                    Text("  ·  ")
                        .foregroundStyle(.tertiary)

                    Text(objectName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                if isExpanded {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        if claim.objectEntityId != nil {
                            Label("Object: entity", systemImage: "person.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let value = claim.value {
                            Label("Value: \(value)", systemImage: "text.quote")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if claim.memoryId != nil {
                            Label("Sourced from memory", systemImage: "note.text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Recorded \(DateUtils.relativeString(from: claim.createdAt))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text(DateUtils.relativeString(from: claim.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, isExpanded ? 8 : 4)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.18), value: isExpanded)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ClaimListView()
    }
    .modelContainer(DatabaseController.previewContainer())
}
