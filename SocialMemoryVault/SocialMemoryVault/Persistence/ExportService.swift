import Foundation
import SwiftData

// MARK: - Codable export shapes

struct ExportedEntity: Codable {
    let id: String
    let entityType: String
    let canonicalName: String
    let notes: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case entityType = "entity_type"
        case canonicalName = "canonical_name"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ExportedEntityAlias: Codable {
    let id: String
    let entityId: String
    let alias: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case entityId = "entity_id"
        case alias
        case createdAt = "created_at"
    }
}

struct ExportedMemory: Codable {
    let id: String
    let body: String
    let summary: String?
    let occurredAt: String?
    let createdAt: String
    let updatedAt: String
    let privacyLevel: String

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case summary
        case occurredAt = "occurred_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case privacyLevel = "privacy_level"
    }
}

struct ExportedMemoryEntityLink: Codable {
    let id: String
    let memoryId: String
    let entityId: String
    let role: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case memoryId = "memory_id"
        case entityId = "entity_id"
        case role
        case createdAt = "created_at"
    }
}

struct ExportedClaim: Codable {
    let id: String
    let subjectEntityId: String
    let predicate: String
    let objectEntityId: String?
    let value: String?
    let memoryId: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case subjectEntityId = "subject_entity_id"
        case predicate
        case objectEntityId = "object_entity_id"
        case value
        case memoryId = "memory_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ExportDocument: Codable {
    let schemaVersion: String
    let exportedAt: String
    let exportMode: String
    let entities: [ExportedEntity]
    let entityAliases: [ExportedEntityAlias]
    let memories: [ExportedMemory]
    let memoryEntityLinks: [ExportedMemoryEntityLink]
    let claims: [ExportedClaim]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case exportedAt = "exported_at"
        case exportMode = "export_mode"
        case entities
        case entityAliases = "entity_aliases"
        case memories
        case memoryEntityLinks = "memory_entity_links"
        case claims
    }
}

// MARK: - ExportService

enum ExportError: Error, LocalizedError {
    case encodingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .encodingFailed(let underlying):
            return "Export encoding failed: \(underlying.localizedDescription)"
        }
    }
}

struct ExportService {

    /// Export all data to JSON.
    /// - Parameters:
    ///   - context: The SwiftData ModelContext to fetch from.
    ///   - excludeSensitive: When true, memories (and their associated links/claims)
    ///     whose privacyLevel is `.doNotExport` are omitted from the output.
    /// - Returns: UTF-8 JSON data representing the full export document.
    static func export(context: ModelContext, excludeSensitive: Bool) throws -> Data {
        let exportMode = excludeSensitive ? "standard" : "full"

        // MARK: Fetch entities
        let entityDescriptor = FetchDescriptor<Entity>(sortBy: [SortDescriptor(\.createdAt)])
        let allEntities = (try? context.fetch(entityDescriptor)) ?? []

        // MARK: Fetch aliases
        let aliasDescriptor = FetchDescriptor<EntityAlias>(sortBy: [SortDescriptor(\.createdAt)])
        let allAliases = (try? context.fetch(aliasDescriptor)) ?? []

        // MARK: Fetch memories (with optional privacy filter)
        let memoryDescriptor = FetchDescriptor<Memory>(sortBy: [SortDescriptor(\.createdAt)])
        let allMemories = (try? context.fetch(memoryDescriptor)) ?? []
        let filteredMemories: [Memory]
        if excludeSensitive {
            filteredMemories = allMemories.filter { $0.privacyLevel != PrivacyLevel.doNotExport.rawValue }
        } else {
            filteredMemories = allMemories
        }
        let allowedMemoryIds = Set(filteredMemories.map { $0.id })

        // MARK: Fetch memory-entity links
        let linkDescriptor = FetchDescriptor<MemoryEntityLink>(sortBy: [SortDescriptor(\.createdAt)])
        let allLinks = (try? context.fetch(linkDescriptor)) ?? []
        let filteredLinks: [MemoryEntityLink]
        if excludeSensitive {
            filteredLinks = allLinks.filter { allowedMemoryIds.contains($0.memoryId) }
        } else {
            filteredLinks = allLinks
        }

        // MARK: Fetch claims
        let claimDescriptor = FetchDescriptor<Claim>(sortBy: [SortDescriptor(\.createdAt)])
        let allClaims = (try? context.fetch(claimDescriptor)) ?? []
        let filteredClaims: [Claim]
        if excludeSensitive {
            filteredClaims = allClaims.filter { claim in
                guard let memId = claim.memoryId else { return true }
                return allowedMemoryIds.contains(memId)
            }
        } else {
            filteredClaims = allClaims
        }

        // MARK: Build Codable shapes
        let exportedEntities = allEntities.map { entity in
            ExportedEntity(
                id: entity.id,
                entityType: entity.entityType,
                canonicalName: entity.canonicalName,
                notes: entity.notes,
                createdAt: DateUtils.isoString(from: entity.createdAt),
                updatedAt: DateUtils.isoString(from: entity.updatedAt)
            )
        }

        let exportedAliases = allAliases.map { alias in
            ExportedEntityAlias(
                id: alias.id,
                entityId: alias.entityId,
                alias: alias.alias,
                createdAt: DateUtils.isoString(from: alias.createdAt)
            )
        }

        let exportedMemories = filteredMemories.map { memory in
            ExportedMemory(
                id: memory.id,
                body: memory.body,
                summary: memory.summary,
                occurredAt: memory.occurredAt.map { DateUtils.isoString(from: $0) },
                createdAt: DateUtils.isoString(from: memory.createdAt),
                updatedAt: DateUtils.isoString(from: memory.updatedAt),
                privacyLevel: memory.privacyLevel
            )
        }

        let exportedLinks = filteredLinks.map { link in
            ExportedMemoryEntityLink(
                id: link.id,
                memoryId: link.memoryId,
                entityId: link.entityId,
                role: link.role,
                createdAt: DateUtils.isoString(from: link.createdAt)
            )
        }

        let exportedClaims = filteredClaims.map { claim in
            ExportedClaim(
                id: claim.id,
                subjectEntityId: claim.subjectEntityId,
                predicate: claim.predicate,
                objectEntityId: claim.objectEntityId,
                value: claim.value,
                memoryId: claim.memoryId,
                createdAt: DateUtils.isoString(from: claim.createdAt),
                updatedAt: DateUtils.isoString(from: claim.updatedAt)
            )
        }

        let document = ExportDocument(
            schemaVersion: "0.1",
            exportedAt: DateUtils.isoString(from: Date()),
            exportMode: exportMode,
            entities: exportedEntities,
            entityAliases: exportedAliases,
            memories: exportedMemories,
            memoryEntityLinks: exportedLinks,
            claims: exportedClaims
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            return try encoder.encode(document)
        } catch {
            throw ExportError.encodingFailed(underlying: error)
        }
    }
}
