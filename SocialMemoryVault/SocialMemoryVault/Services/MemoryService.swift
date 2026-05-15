import Foundation
import SwiftData

struct MemoryService {

    // MARK: - All memories, newest first
    static func fetchAll(in context: ModelContext) -> [Memory] {
        var descriptor = FetchDescriptor<Memory>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Most recent N memories
    static func fetchRecent(limit: Int, in context: ModelContext) -> [Memory] {
        var descriptor = FetchDescriptor<Memory>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - All memories linked to a given entity (via MemoryEntityLink)
    static func fetchLinked(to entityId: String, in context: ModelContext) -> [Memory] {
        // First, collect the memoryIds that reference this entity
        let linkDescriptor = FetchDescriptor<MemoryEntityLink>(
            predicate: #Predicate { $0.entityId == entityId }
        )
        let links = (try? context.fetch(linkDescriptor)) ?? []
        let memoryIds = Set(links.map(\.memoryId))
        guard !memoryIds.isEmpty else { return [] }

        var memoryDescriptor = FetchDescriptor<Memory>(
            predicate: #Predicate { memoryIds.contains($0.id) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(memoryDescriptor)) ?? []
    }

    // MARK: - All MemoryEntityLinks for a given memory
    static func fetchLinks(for memoryId: String, in context: ModelContext) -> [MemoryEntityLink] {
        var descriptor = FetchDescriptor<MemoryEntityLink>(
            predicate: #Predicate { $0.memoryId == memoryId },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - All MemoryEntityLinks for a given entity
    static func fetchLinks(for entityId: String, in context: ModelContext) -> [MemoryEntityLink] {
        var descriptor = FetchDescriptor<MemoryEntityLink>(
            predicate: #Predicate { $0.entityId == entityId },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Delete a memory and all its associated MemoryEntityLinks
    static func delete(_ memory: Memory, in context: ModelContext) {
        // Remove links first
        let links = fetchLinks(for: memory.id, in: context)
        for link in links {
            context.delete(link)
        }
        context.delete(memory)
    }
}
