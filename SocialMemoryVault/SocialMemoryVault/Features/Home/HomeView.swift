import SwiftUI
import SwiftData

/// The Home tab root view.
/// Must be embedded inside a NavigationStack (provided by ContentView / TabView).
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Memory.createdAt, order: .reverse)
    private var allMemories: [Memory]

    @Query(sort: \Entity.updatedAt, order: .reverse)
    private var allEntities: [Entity]

    @Query private var allLinks: [MemoryEntityLink]

    @State private var showAddMemory = false

    private var recentMemories: [Memory] { Array(allMemories.prefix(5)) }
    private var recentEntities: [Entity] { Array(allEntities.prefix(5)) }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Search bar — navigates to SearchView on tap
                    NavigationLink(destination: SearchView()) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            Text("Search memories and entities…")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)

                    // Add Memory CTA
                    Button {
                        showAddMemory = true
                    } label: {
                        Label("Add Memory", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal)

                    // Recent Memories section
                    HomeSectionView(title: "Recent Memories", systemImage: "clock") {
                        if recentMemories.isEmpty {
                            HomeEmptyStateRow(
                                message: "No memories yet. Tap \"Add Memory\" to get started."
                            )
                        } else {
                            ForEach(recentMemories) { memory in
                                NavigationLink(destination: MemoryDetailView(memory: memory)) {
                                    MemoryCardRow(memory: memory, links: allLinks)
                                }
                                .buttonStyle(.plain)

                                if memory.id != recentMemories.last?.id {
                                    Divider().padding(.leading)
                                }
                            }
                        }
                    }

                    // Recent Entities section
                    HomeSectionView(title: "Recent Entities", systemImage: "person.2") {
                        if recentEntities.isEmpty {
                            HomeEmptyStateRow(message: "No entities yet.")
                        } else {
                            ForEach(recentEntities) { entity in
                                NavigationLink(destination: EntityDetailView(entity: entity)) {
                                    EntityRowCompact(entity: entity)
                                }
                                .buttonStyle(.plain)

                                if entity.id != recentEntities.last?.id {
                                    Divider().padding(.leading, 52)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 32)
                }
                .padding(.top, 12)
            }
        }
        .navigationTitle("Vault")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showAddMemory) {
            AddEditMemoryView()
        }
    }
}

// MARK: - Section Container

private struct HomeSectionView<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
        }
    }
}

// MARK: - Memory Card Row

private struct MemoryCardRow: View {
    let memory: Memory
    let links: [MemoryEntityLink]

    private var entityCount: Int {
        links.filter { $0.memoryId == memory.id }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(memory.body)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Text(DateUtils.relativeString(from: memory.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if entityCount > 0 {
                    Label("\(entityCount)", systemImage: "person.2.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Entity Compact Row

private struct EntityRowCompact: View {
    let entity: Entity

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(entityTypeColor(entity.entityTypeEnum).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: entity.entityTypeEnum.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(entityTypeColor(entity.entityTypeEnum))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entity.canonicalName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(entity.entityTypeEnum.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.secondary.opacity(0.5))
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Empty State Row

private struct HomeEmptyStateRow: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Entity Type Color
// Module-level free function accessible to all views in this target.

func entityTypeColor(_ type: EntityType) -> Color {
    switch type {
    case .person:       return .blue
    case .place:        return .green
    case .organization: return .orange
    case .concept:      return .purple
    case .object:       return .brown
    case .event:        return .red
    case .unknown:      return .gray
    }
}

// MARK: - Preview
// Wraps HomeView in a NavigationStack to mirror ContentView embedding.

#Preview {
    NavigationStack {
        HomeView()
    }
    .modelContainer(DatabaseController.previewContainer())
}
