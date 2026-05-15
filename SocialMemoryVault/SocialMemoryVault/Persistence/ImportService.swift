import Foundation
import SwiftData

// MARK: - Import result

struct ImportResult {
    var entitiesImported: Int = 0
    var aliasesImported: Int = 0
    var memoriesImported: Int = 0
    var linksImported: Int = 0
    var claimsImported: Int = 0

    var totalImported: Int {
        entitiesImported + aliasesImported + memoriesImported + linksImported + claimsImported
    }

    var summary: String {
        """
        Import complete:
          Entities:      \(entitiesImported)
          Aliases:       \(aliasesImported)
          Memories:      \(memoriesImported)
          Links:         \(linksImported)
          Claims:        \(claimsImported)
          Total:         \(totalImported)
        """
    }
}

// MARK: - Import errors

enum ImportError: Error, LocalizedError {
    case invalidData
    case decodingFailed(underlying: Error)
    case unsupportedSchemaVersion(String)
    case saveFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "The import data is invalid or empty."
        case .decodingFailed(let underlying):
            return "Failed to decode import file: \(underlying.localizedDescription)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported schema version '\(version)'. Only version '0.1' is supported."
        case .saveFailed(let underlying):
            return "Failed to save imported data: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - ImportService

struct ImportService {

    /// Import data from a JSON export document into the given ModelContext.
    /// Duplicate records (matched by `id`) are silently skipped.
    /// - Parameters:
    ///   - data: Raw JSON data in the ExportDocument format.
    ///   - context: The SwiftData ModelContext to insert records into.
    /// - Returns: An `ImportResult` with counts of newly imported records.
    static func importData(_ data: Data, into context: ModelContext) throws -> ImportResult {
        guard !data.isEmpty else { throw ImportError.invalidData }

        let decoder = JSONDecoder()
        let document: ExportDocument
        do {
            document = try decoder.decode(ExportDocument.self, from: data)
        } catch {
            throw ImportError.decodingFailed(underlying: error)
        }

        guard document.schemaVersion == "0.1" else {
            throw ImportError.unsupportedSchemaVersion(document.schemaVersion)
        }

        var result = ImportResult()

        // MARK: Build existing-id sets to detect duplicates

        let existingEntityIds = fetchExistingIds(Entity.self, keyPath: \.id, context: context)
        let existingAliasIds = fetchExistingIds(EntityAlias.self, keyPath: \.id, context: context)
        let existingMemoryIds = fetchExistingIds(Memory.self, keyPath: \.id, context: context)
        let existingLinkIds = fetchExistingIds(MemoryEntityLink.self, keyPath: \.id, context: context)
        let existingClaimIds = fetchExistingIds(Claim.self, keyPath: \.id, context: context)

        // MARK: Import entities

        for exported in document.entities {
            guard !existingEntityIds.contains(exported.id) else { continue }
            let entityType = EntityType(rawValue: exported.entityType) ?? .unknown
            let entity = Entity(
                id: exported.id,
                entityType: entityType,
                canonicalName: exported.canonicalName,
                notes: exported.notes
            )
            // Restore original timestamps
            if let createdAt = DateUtils.date(from: exported.createdAt) {
                entity.createdAt = createdAt
            }
            if let updatedAt = DateUtils.date(from: exported.updatedAt) {
                entity.updatedAt = updatedAt
            }
            context.insert(entity)
            result.entitiesImported += 1
        }

        // MARK: Import aliases

        for exported in document.entityAliases {
            guard !existingAliasIds.contains(exported.id) else { continue }
            let alias = EntityAlias(
                id: exported.id,
                entityId: exported.entityId,
                alias: exported.alias
            )
            if let createdAt = DateUtils.date(from: exported.createdAt) {
                alias.createdAt = createdAt
            }
            context.insert(alias)
            result.aliasesImported += 1
        }

        // MARK: Import memories

        for exported in document.memories {
            guard !existingMemoryIds.contains(exported.id) else { continue }
            let privacyLevel = PrivacyLevel(rawValue: exported.privacyLevel) ?? .normal
            let occurredAt: Date? = exported.occurredAt.flatMap { DateUtils.date(from: $0) }
            let memory = Memory(
                id: exported.id,
                body: exported.body,
                summary: exported.summary,
                occurredAt: occurredAt,
                privacyLevel: privacyLevel
            )
            if let createdAt = DateUtils.date(from: exported.createdAt) {
                memory.createdAt = createdAt
            }
            if let updatedAt = DateUtils.date(from: exported.updatedAt) {
                memory.updatedAt = updatedAt
            }
            context.insert(memory)
            result.memoriesImported += 1
        }

        // MARK: Import memory-entity links

        for exported in document.memoryEntityLinks {
            guard !existingLinkIds.contains(exported.id) else { continue }
            let role = LinkRole(rawValue: exported.role) ?? .unknown
            let link = MemoryEntityLink(
                id: exported.id,
                memoryId: exported.memoryId,
                entityId: exported.entityId,
                role: role
            )
            if let createdAt = DateUtils.date(from: exported.createdAt) {
                link.createdAt = createdAt
            }
            context.insert(link)
            result.linksImported += 1
        }

        // MARK: Import claims

        for exported in document.claims {
            guard !existingClaimIds.contains(exported.id) else { continue }
            let claim = Claim(
                id: exported.id,
                subjectEntityId: exported.subjectEntityId,
                predicate: exported.predicate,
                objectEntityId: exported.objectEntityId,
                value: exported.value,
                memoryId: exported.memoryId
            )
            if let createdAt = DateUtils.date(from: exported.createdAt) {
                claim.createdAt = createdAt
            }
            if let updatedAt = DateUtils.date(from: exported.updatedAt) {
                claim.updatedAt = updatedAt
            }
            context.insert(claim)
            result.claimsImported += 1
        }

        // MARK: Persist

        do {
            try context.save()
        } catch {
            throw ImportError.saveFailed(underlying: error)
        }

        return result
    }

    // MARK: - Private helpers

    /// Fetch all existing string IDs for a given model type, returning them as a Set.
    private static func fetchExistingIds<T: PersistentModel>(
        _ type: T.Type,
        keyPath: KeyPath<T, String>,
        context: ModelContext
    ) -> Set<String> {
        let descriptor = FetchDescriptor<T>()
        let models = (try? context.fetch(descriptor)) ?? []
        return Set(models.map { $0[keyPath: keyPath] })
    }
}
