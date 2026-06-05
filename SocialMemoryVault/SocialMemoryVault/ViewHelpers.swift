import SwiftUI
import SwiftData

func entityTypeColor(_ type: EntityType) -> Color {
    switch type {
    case .person: return .blue
    case .organization: return .purple
    case .place: return .orange
    case .thing: return .teal
    }
}

extension ModelContext {
    func delete<M: PersistentModel>(model: M.Type) throws {
        var descriptor = FetchDescriptor<M>()
        let all = try fetch(descriptor)
        for obj in all { delete(obj) }
    }
}
