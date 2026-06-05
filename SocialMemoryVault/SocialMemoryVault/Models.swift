import Foundation
import SwiftData

public enum LinkRole: String, Codable, Sendable {
    case participant
    case location
}

@Model
public final class Entity {
    public var id: String
    public var entityType: String
    public var canonicalName: String
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, entityType: EntityType, canonicalName: String, notes: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.entityType = entityType.rawValue
        self.canonicalName = canonicalName
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var entityTypeEnum: EntityType {
        get { EntityType(rawValue: entityType) ?? .thing }
        set { entityType = newValue.rawValue }
    }
}

@Model
public final class EntityAlias {
    public var id: String
    public var entityId: String
    public var alias: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, entityId: String, alias: String, createdAt: Date = Date()) {
        self.id = id
        self.entityId = entityId
        self.alias = alias
        self.createdAt = createdAt
    }
}

@Model
public final class Memory {
    public var id: String
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
    public var privacyLevel: String

    public init(id: String = UUID().uuidString, body: String, createdAt: Date = Date(), updatedAt: Date = Date(), privacyLevel: PrivacyLevel = .normal) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.privacyLevel = privacyLevel.rawValue
    }

    public var privacyLevelEnum: PrivacyLevel {
        get { PrivacyLevel(rawValue: privacyLevel) ?? .normal }
        set { privacyLevel = newValue.rawValue }
    }
}

@Model
public final class MemoryEntityLink {
    public var id: String
    public var memoryId: String
    public var entityId: String
    public var role: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, memoryId: String, entityId: String, role: LinkRole, createdAt: Date = Date()) {
        self.id = id
        self.memoryId = memoryId
        self.entityId = entityId
        self.role = role.rawValue
        self.createdAt = createdAt
    }
}

@Model
public final class Claim {
    public var id: String
    public var subjectEntityId: String
    public var predicate: String
    public var objectEntityId: String?
    public var value: String?
    public var memoryId: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, subjectEntityId: String, predicate: String, objectEntityId: String? = nil, value: String? = nil, memoryId: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.subjectEntityId = subjectEntityId
        self.predicate = predicate
        self.objectEntityId = objectEntityId
        self.value = value
        self.memoryId = memoryId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
