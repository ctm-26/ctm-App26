import Foundation
import SwiftData

struct ClaimService {

    // MARK: - All claims, newest first
    static func fetchAll(in context: ModelContext) -> [Claim] {
        let descriptor = FetchDescriptor<Claim>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Claims where the subject entity matches
    static func fetchClaims(forSubject entityId: String, in context: ModelContext) -> [Claim] {
        var descriptor = FetchDescriptor<Claim>(
            predicate: #Predicate { $0.subjectEntityId == entityId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Claims where the object entity matches
    static func fetchClaims(forObject entityId: String, in context: ModelContext) -> [Claim] {
        var descriptor = FetchDescriptor<Claim>(
            predicate: #Predicate { $0.objectEntityId == entityId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Claims sourced from a specific memory
    static func fetchClaims(forMemory memoryId: String, in context: ModelContext) -> [Claim] {
        var descriptor = FetchDescriptor<Claim>(
            predicate: #Predicate { $0.memoryId == memoryId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Claims with an exact predicate string
    static func fetchClaims(withPredicate predicate: String, in context: ModelContext) -> [Claim] {
        var descriptor = FetchDescriptor<Claim>(
            predicate: #Predicate { $0.predicate == predicate },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
