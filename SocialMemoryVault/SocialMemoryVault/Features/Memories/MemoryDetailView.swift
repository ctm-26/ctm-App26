import SwiftUI
import SwiftData

struct MemoryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let memory: Memory

    @State private var links: [MemoryEntityLink] = []
    @State private var claims: [Claim] = []
    @State private var showEditMemory = false
    @State private var showEntityLinker = false
    @State private var showAddClaim = false

    // Group links by role
    private var linksByRole: [(role: LinkRole, links: [MemoryEntityLink])] {
        let grouped = Dictionary(grouping: links) { $0.roleEnum }
        return LinkRole.allCases.compactMap { role in
            let roleLinks = grouped[role] ?? []
            return roleLinks.isEmpty ? nil : (role: role, links: roleLinks)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: Body
                VStack(alignment: .leading, spacing: 12) {
                    Text(memory.body)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 16)

                // MARK: Metadata
                VStack(alignment: .leading, spacing: 0) {
                    if let summary = memory.summary, !summary.isEmpty {
                        DetailMetaRow(label: "Summary", value: summary)
                        Divider().padding(.leading, 16)
                    }

                    if let occurredAt = memory.occurredAt {
                        DetailMetaRow(label: "Occurred", value: DateUtils.display(occurredAt))
                        Divider().padding(.leading, 16)
                    }

                    // Privacy badge
                    HStack {
                        Text("Privacy")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label(memory.privacyLevelEnum.displayName,
                              systemImage: memory.privacyLevelEnum.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(privacyColor(memory.privacyLevelEnum))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(privacyColor(memory.privacyLevelEnum).opacity(0.12),
                                        in: Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 12)

                // MARK: Linked Entities
                DetailSectionHeader(title: "Linked Entities", systemImage: "person.2.fill")
                    .padding(.top, 20)

                if links.isEmpty {
                    DetailEmptyState(message: "No entities linked yet.", action: {
                        showEntityLinker = true
                    }, actionLabel: "Link Entity")
                    .padding(.horizontal)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(linksByRole, id: \.role) { group in
                            Section {
                                ForEach(group.links) { link in
                                    let entity = EntityResolutionService.findEntity(byId: link.entityId, in: modelContext)
                                    NavigationLink {
                                        if let entity = entity {
                                            EntityDetailView(entity: entity)
                                        }
                                    } label: {
                                        LinkedEntityRow(
                                            entityName: entity?.canonicalName ?? "Unknown Entity",
                                            entityType: entity?.entityTypeEnum ?? .unknown,
                                            role: link.roleEnum
                                        )
                                    }
                                    .disabled(entity == nil)

                                    if link.id != group.links.last?.id {
                                        Divider().padding(.leading, 56)
                                    }
                                }
                            } header: {
                                Text(group.role.displayName.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .tracking(0.5)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // MARK: Claims
                DetailSectionHeader(title: "Claims from this Memory", systemImage: "checkmark.seal.fill")
                    .padding(.top, 20)

                if claims.isEmpty {
                    DetailEmptyState(message: "No claims sourced from this memory.", action: {
                        showAddClaim = true
                    }, actionLabel: "Add Claim")
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 0) {
                        ForEach(claims) { claim in
                            ClaimSummaryRow(claim: claim, context: modelContext)

                            if claim.id != claims.last?.id {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // MARK: Footer Dates
                VStack(alignment: .leading, spacing: 4) {
                    Text("Created \(DateUtils.display(memory.createdAt))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("Updated \(DateUtils.display(memory.updatedAt))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showAddClaim = true
                } label: {
                    Image(systemName: "checkmark.seal")
                }
                .accessibilityLabel("Add Claim")

                Button {
                    showEntityLinker = true
                } label: {
                    Image(systemName: "link.badge.plus")
                }
                .accessibilityLabel("Link Entity")

                Button {
                    showEditMemory = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit Memory")
            }
        }
        .sheet(isPresented: $showEditMemory, onDismiss: { reload() }) {
            AddEditMemoryView(memory: memory)
        }
        .sheet(isPresented: $showEntityLinker, onDismiss: { reload() }) {
            EntityLinkerView(memory: memory)
        }
        .sheet(isPresented: $showAddClaim, onDismiss: { reload() }) {
            AddEditClaimView(memoryId: memory.id)
        }
        .onAppear { reload() }
    }

    private func reload() {
        links = MemoryService.fetchLinks(for: memory.id, in: modelContext)
        claims = ClaimService.fetchClaims(forMemory: memory.id, in: modelContext)
    }

    private func privacyColor(_ level: PrivacyLevel) -> Color {
        switch level {
        case .normal: return .secondary
        case .sensitive: return .orange
        case .doNotExport: return .red
        }
    }
}

// MARK: - Sub-views

private struct DetailMetaRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct DetailSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}

private struct DetailEmptyState: View {
    let message: String
    let action: () -> Void
    let actionLabel: String

    var body: some View {
        HStack {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: action) {
                Text(actionLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(.accentColor)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct LinkedEntityRow: View {
    let entityName: String
    let entityType: EntityType
    let role: LinkRole

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(entityTypeColor(entityType).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: entityType.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(entityTypeColor(entityType))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entityName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Label(role.displayName, systemImage: role.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.secondary.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct ClaimSummaryRow: View {
    let claim: Claim
    let context: ModelContext

    private var subjectName: String {
        EntityResolutionService.findEntity(byId: claim.subjectEntityId, in: context)?.canonicalName ?? claim.subjectEntityId
    }

    private var objectDisplay: String {
        if let oid = claim.objectEntityId,
           let entity = EntityResolutionService.findEntity(byId: oid, in: context) {
            return entity.canonicalName
        }
        return claim.value ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(subjectName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(claim.predicate)
                    .font(.subheadline)
                    .foregroundStyle(.accentColor)
                    .italic()
            }
            Text(objectDisplay)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MemoryDetailView(memory: Memory(body: "Had a long conversation with Alex about the hiking trip planned for next summer. They seem really excited about it.", summary: "Alex excited about hiking", privacyLevel: .normal))
    }
    .modelContainer(DatabaseController.previewContainer())
}
