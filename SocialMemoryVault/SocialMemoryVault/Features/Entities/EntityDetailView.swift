import SwiftUI
import SwiftData

struct EntityDetailView: View {
    let entity: Entity

    @Environment(\.modelContext) private var modelContext

    @Query private var allAliases: [EntityAlias]
    @Query private var allLinks: [MemoryEntityLink]
    @Query(sort: \Memory.createdAt, order: .reverse) private var allMemories: [Memory]
    @Query(sort: \Claim.createdAt, order: .reverse) private var allClaims: [Claim]

    @State private var showEditEntity = false
    @State private var showAliasManager = false
    @State private var showAddMemory = false
    @State private var showAddClaim = false

    // MARK: - Derived Data

    private var aliases: [EntityAlias] {
        allAliases.filter { $0.entityId == entity.id }
    }

    private var subjectClaims: [Claim] {
        allClaims.filter { $0.subjectEntityId == entity.id }
    }

    private var objectClaims: [Claim] {
        allClaims.filter { $0.objectEntityId == entity.id }
    }

    private var linkedLinks: [MemoryEntityLink] {
        allLinks.filter { $0.entityId == entity.id }
    }

    private var linkedMemories: [(memory: Memory, link: MemoryEntityLink)] {
        linkedLinks.compactMap { link in
            guard let memory = allMemories.first(where: { $0.id == link.memoryId }) else { return nil }
            return (memory: memory, link: link)
        }
        .sorted { $0.memory.createdAt > $1.memory.createdAt }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero header
                heroHeader

                // Content sections
                VStack(alignment: .leading, spacing: 20) {
                    // Notes
                    if let notes = entity.notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
                        DetailSection(title: "Notes", systemImage: "note.text") {
                            Text(notes)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    // Aliases
                    DetailSection(title: "Aliases", systemImage: "person.badge.plus") {
                        VStack(alignment: .leading, spacing: 0) {
                            if aliases.isEmpty {
                                Text("No aliases")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding()
                            } else {
                                ForEach(aliases) { alias in
                                    HStack {
                                        Text(alias.alias)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 10)

                                    if alias.id != aliases.last?.id {
                                        Divider().padding(.leading)
                                    }
                                }
                            }

                            Divider()

                            Button {
                                showAliasManager = true
                            } label: {
                                Label("Manage Aliases", systemImage: "square.and.pencil")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        }
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Claims as Subject
                    if !subjectClaims.isEmpty {
                        DetailSection(title: "Claims (as Subject)", systemImage: "arrow.right.circle") {
                            VStack(spacing: 0) {
                                ForEach(subjectClaims) { claim in
                                    ClaimRowView(claim: claim, modelContext: modelContext)

                                    if claim.id != subjectClaims.last?.id {
                                        Divider().padding(.leading)
                                    }
                                }
                            }
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    // Claims as Object
                    if !objectClaims.isEmpty {
                        DetailSection(title: "Claims (as Object)", systemImage: "arrow.left.circle") {
                            VStack(spacing: 0) {
                                ForEach(objectClaims) { claim in
                                    ClaimRowView(claim: claim, modelContext: modelContext, perspective: .asObject)

                                    if claim.id != objectClaims.last?.id {
                                        Divider().padding(.leading)
                                    }
                                }
                            }
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    // Memories
                    DetailSection(title: "Memories", systemImage: "text.book.closed") {
                        VStack(spacing: 0) {
                            if linkedMemories.isEmpty {
                                Text("No memories linked to this entity.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(linkedMemories, id: \.memory.id) { item in
                                    NavigationLink(destination: MemoryDetailView(memory: item.memory)) {
                                        LinkedMemoryRow(memory: item.memory, link: item.link)
                                    }
                                    .buttonStyle(.plain)

                                    if item.memory.id != linkedMemories.last?.memory.id {
                                        Divider().padding(.leading)
                                    }
                                }
                            }
                        }
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal)
                .padding(.top, 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showEditEntity = true
                    } label: {
                        Label("Edit Entity", systemImage: "pencil")
                    }

                    Divider()

                    Button {
                        showAddMemory = true
                    } label: {
                        Label("Add Memory", systemImage: "plus.circle")
                    }

                    Button {
                        showAddClaim = true
                    } label: {
                        Label("Add Claim", systemImage: "arrow.right.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditEntity) {
            AddEditEntityView(entity: entity)
        }
        .sheet(isPresented: $showAliasManager) {
            AliasManagerView(entity: entity)
        }
        .sheet(isPresented: $showAddMemory) {
            AddEditMemoryView(initialEntityId: entity.id)
        }
        .sheet(isPresented: $showAddClaim) {
            AddEditClaimView(subjectEntityId: entity.id)
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(entityTypeColor(entity.entityTypeEnum).opacity(0.18))
                    .frame(width: 80, height: 80)
                Image(systemName: entity.entityTypeEnum.systemImage)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(entityTypeColor(entity.entityTypeEnum))
            }

            VStack(spacing: 6) {
                Text(entity.canonicalName)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(entity.entityTypeEnum.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(entityTypeColor(entity.entityTypeEnum), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal)
    }
}

// MARK: - Detail Section Container

private struct DetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }

            content()
        }
    }
}

// MARK: - Claim Row

private struct ClaimRowView: View {
    let claim: Claim
    let modelContext: ModelContext
    var perspective: ClaimPerspective = .asSubject

    enum ClaimPerspective { case asSubject, asObject }

    private var objectName: String? {
        guard let oid = claim.objectEntityId else { return nil }
        return EntityResolutionService.findEntity(byId: oid, in: modelContext)?.canonicalName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch perspective {
            case .asSubject:
                HStack(spacing: 4) {
                    Text(claim.predicate)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let name = objectName {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.accentColor)
                    } else if let value = claim.value {
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            case .asObject:
                HStack(spacing: 4) {
                    if let subjectEntity = EntityResolutionService.findEntity(byId: claim.subjectEntityId, in: modelContext) {
                        Text(subjectEntity.canonicalName)
                            .font(.subheadline)
                            .foregroundStyle(.accentColor)
                    } else {
                        Text(claim.subjectEntityId)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(claim.predicate)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Linked Memory Row

private struct LinkedMemoryRow: View {
    let memory: Memory
    let link: MemoryEntityLink

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(memory.body)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Text(DateUtils.relativeString(from: memory.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(link.roleEnum.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    let container = DatabaseController.previewContainer()
    let entity = Entity(entityType: .person, canonicalName: "Alice Smith", notes: "Old friend from university.")
    container.mainContext.insert(entity)

    return NavigationStack {
        EntityDetailView(entity: entity)
    }
    .modelContainer(container)
}
