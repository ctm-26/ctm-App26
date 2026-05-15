import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var allEntities: [Entity]
    @Query private var allMemories: [Memory]
    @Query private var allClaims: [Claim]

    @State private var searchText: String = ""
    @State private var segment: SearchSegment = .all
    @State private var debouncedText: String = ""
    @State private var debounceTask: Task<Void, Never>? = nil

    enum SearchSegment: String, CaseIterable {
        case all = "All"
        case entities = "Entities"
        case memories = "Memories"
        case claims = "Claims"
    }

    // MARK: - Filtered Results

    private var matchingEntities: [Entity] {
        guard !debouncedText.isEmpty else { return [] }
        return allEntities.filter {
            $0.canonicalName.localizedStandardContains(debouncedText)
        }
    }

    private var matchingMemories: [Memory] {
        guard !debouncedText.isEmpty else { return [] }
        return allMemories.filter {
            $0.body.localizedStandardContains(debouncedText)
            || ($0.summary?.localizedStandardContains(debouncedText) == true)
        }
    }

    private var matchingClaims: [Claim] {
        guard !debouncedText.isEmpty else { return [] }
        let lower = debouncedText.lowercased()
        return allClaims.filter { claim in
            if claim.predicate.lowercased().contains(lower) { return true }
            if let value = claim.value, value.lowercased().contains(lower) { return true }
            // entity name match
            if let subject = allEntities.first(where: { $0.id == claim.subjectEntityId }),
               subject.canonicalName.lowercased().contains(lower) { return true }
            if let oid = claim.objectEntityId,
               let obj = allEntities.first(where: { $0.id == oid }),
               obj.canonicalName.lowercased().contains(lower) { return true }
            return false
        }
    }

    private var hasResults: Bool {
        switch segment {
        case .all: return !matchingEntities.isEmpty || !matchingMemories.isEmpty || !matchingClaims.isEmpty
        case .entities: return !matchingEntities.isEmpty
        case .memories: return !matchingMemories.isEmpty
        case .claims: return !matchingClaims.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segment control
            Picker("Scope", selection: $segment) {
                ForEach(SearchSegment.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            if searchText.isEmpty {
                emptyPromptView
            } else if debouncedText.isEmpty {
                // Typing but not yet debounced
                Color.clear
            } else if !hasResults {
                noResultsView
            } else {
                resultsList
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search people, places, memories…")
        .onChange(of: searchText) { _, newValue in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                if !Task.isCancelled {
                    debouncedText = newValue
                }
            }
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            if segment == .all || segment == .entities {
                if !matchingEntities.isEmpty {
                    Section {
                        ForEach(matchingEntities) { entity in
                            NavigationLink {
                                EntityDetailView(entity: entity)
                            } label: {
                                SearchEntityRow(entity: entity, query: debouncedText)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Entities")
                            Spacer()
                            Text("\(matchingEntities.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if segment == .all || segment == .memories {
                if !matchingMemories.isEmpty {
                    Section {
                        ForEach(matchingMemories) { memory in
                            NavigationLink {
                                MemoryDetailView(memory: memory)
                            } label: {
                                SearchMemoryRow(memory: memory, query: debouncedText)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Memories")
                            Spacer()
                            Text("\(matchingMemories.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if segment == .all || segment == .claims {
                if !matchingClaims.isEmpty {
                    Section {
                        ForEach(matchingClaims) { claim in
                            SearchClaimRow(
                                claim: claim,
                                subjectName: allEntities.first(where: { $0.id == claim.subjectEntityId })?.canonicalName ?? "Unknown",
                                objectName: objectDisplay(for: claim)
                            )
                        }
                    } header: {
                        HStack {
                            Text("Claims")
                            Spacer()
                            Text("\(matchingClaims.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty / No-results

    private var emptyPromptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("Search Your Vault")
                    .font(.title3.weight(.semibold))
                Text("Find people, places, memories, and claims — everything is stored locally.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Quick segment hints
            HStack(spacing: 12) {
                ForEach(SearchSegment.allCases.dropFirst(), id: \.self) { seg in
                    Text(seg.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)

            Text("No results for \"\(debouncedText)\"")
                .font(.title3.weight(.semibold))

            Text("Try different keywords, or check the filter above.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    // MARK: - Helpers

    private func objectDisplay(for claim: Claim) -> String {
        if let oid = claim.objectEntityId,
           let entity = allEntities.first(where: { $0.id == oid }) {
            return entity.canonicalName
        }
        return claim.value ?? "—"
    }
}

// MARK: - Search Row Subviews

private struct SearchEntityRow: View {
    let entity: Entity
    let query: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(entityTypeColor(entity.entityTypeEnum).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: entity.entityTypeEnum.systemImage)
                    .font(.system(size: 15, weight: .semibold))
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
        }
        .padding(.vertical, 2)
    }
}

private struct SearchMemoryRow: View {
    let memory: Memory
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(memory.body)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack {
                Text(DateUtils.relativeString(from: memory.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                let level = memory.privacyLevelEnum
                if level != .normal {
                    Image(systemName: level.systemImage)
                        .font(.caption2)
                        .foregroundStyle(level == .doNotExport ? .red : .orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SearchClaimRow: View {
    let claim: Claim
    let subjectName: String
    let objectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(subjectName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(claim.predicate)
                    .font(.subheadline)
                    .foregroundStyle(.accentColor)
                    .italic()
                    .lineLimit(1)
            }
            Text(objectName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SearchView()
    }
    .modelContainer(DatabaseController.previewContainer())
}
