import Foundation

public enum EntityType: String, CaseIterable, Codable, Sendable {
    case person
    case organization
    case place
    case thing

    public var displayName: String {
        switch self {
        case .person: return "Person"
        case .organization: return "Organization"
        case .place: return "Place"
        case .thing: return "Thing"
        }
    }

    public var systemImage: String {
        switch self {
        case .person: return "person.fill"
        case .organization: return "building.2.fill"
        case .place: return "mappin.and.ellipse"
        case .thing: return "cube.fill"
        }
    }
}

public enum PrivacyLevel: String, CaseIterable, Codable, Sendable {
    case normal
    case sensitive
    case doNotExport

    public var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .sensitive: return "Sensitive"
        case .doNotExport: return "Do Not Export"
        }
    }

    public var systemImage: String {
        switch self {
        case .normal: return "checkmark.seal.fill"
        case .sensitive: return "exclamationmark.triangle.fill"
        case .doNotExport: return "nosign"
        }
    }
}
