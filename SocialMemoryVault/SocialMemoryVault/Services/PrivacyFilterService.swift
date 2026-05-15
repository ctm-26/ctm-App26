import Foundation

struct PrivacyFilterService {

    // MARK: - Memory export eligibility

    /// Returns true when a memory is eligible for export given the current settings.
    /// - "do_not_export" memories are always excluded.
    /// - "sensitive" memories are excluded when `excludeSensitive` is true.
    static func shouldExport(_ memory: Memory, excludeSensitive: Bool) -> Bool {
        let level = memory.privacyLevelEnum
        switch level {
        case .doNotExport:
            return false
        case .sensitive:
            return !excludeSensitive
        case .normal:
            return true
        }
    }

    // MARK: - Claim export eligibility

    /// Returns true when a claim is eligible for export.
    /// A claim is excluded if its source memory is excluded, OR if `excludeSensitive`
    /// would exclude its source memory.  Claims without a source memory are always
    /// exportable (they have no privacy level of their own).
    static func shouldExport(
        _ claim: Claim,
        memories: [Memory],
        excludeSensitive: Bool
    ) -> Bool {
        guard let memoryId = claim.memoryId, !memoryId.isEmpty else {
            // No source memory — treat as normal
            return true
        }
        guard let sourceMemory = memories.first(where: { $0.id == memoryId }) else {
            // Source memory not found in the provided list — assume it was already filtered
            return false
        }
        return shouldExport(sourceMemory, excludeSensitive: excludeSensitive)
    }

    // MARK: - Batch filtering

    /// Filters a collection of memories according to the export rules.
    static func filterMemories(_ memories: [Memory], excludeSensitive: Bool) -> [Memory] {
        memories.filter { shouldExport($0, excludeSensitive: excludeSensitive) }
    }

    /// Filters a collection of claims according to the export rules.
    static func filterClaims(
        _ claims: [Claim],
        memories: [Memory],
        excludeSensitive: Bool
    ) -> [Claim] {
        claims.filter { shouldExport($0, memories: memories, excludeSensitive: excludeSensitive) }
    }
}
