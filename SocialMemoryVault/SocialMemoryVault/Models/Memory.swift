import Foundation
import SwiftData

enum PrivacyLevel: String, CaseIterable, Codable {
    case normal
    case sensitive
    case doNotExport = "do_not_export"

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .sensitive: return "Sensitive"
        case .doNotExport: return "Do Not Export"
        }
    }

    var systemImage: String {
        switch self {
        case .normal: return "lock.open.fill"
        case .sensitive: return "exclamationmark.shield.fill"
        case .doNotExport: return "lock.fill"
        }
    }
}

@Model
final class Memory {
    var id: String
    var body: String
    var summary: String?
    var occurredAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var privacyLevel: String
    // TODO: embeddings field for semantic search (v0.7)

    init(id: String = IDGenerator.newID(),
         body: String,
         summary: String? = nil,
         occurredAt: Date? = nil,
         privacyLevel: PrivacyLevel = .normal) {
        self.id = id
        self.body = body
        self.summary = summary
        self.occurredAt = occurredAt
        self.createdAt = Date()
        self.updatedAt = Date()
        self.privacyLevel = privacyLevel.rawValue
    }

    var privacyLevelEnum: PrivacyLevel {
        PrivacyLevel(rawValue: privacyLevel) ?? .normal
    }
}
