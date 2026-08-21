import Foundation
import SwiftData

@MainActor
protocol MemoryRepository: AnyObject {
    func fetch(
        profileId: String,
        scopes: [MemoryScope],
        matching query: String,
        now: Date
    ) throws -> [MemoryItem]
    func upsertDebug(_ item: MemoryItem) throws
    func save() throws
}

@MainActor
final class SwiftDataMemoryRepository: MemoryRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetch(
        profileId: String,
        scopes: [MemoryScope],
        matching query: String,
        now: Date
    ) throws -> [MemoryItem] {
        guard !profileId.isEmpty else { throw StoreError.invalidInput }
        let pid = profileId
        let fetched = try context.fetch(
            FetchDescriptor<MemoryItem>(
                predicate: #Predicate { $0.profileId == pid && $0.deletedAt == nil }
            )
        )
        let allowed = Set(scopes.map(\.rawValue))
        let tokens = query.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 }

        return fetched.filter { item in
            guard allowed.contains(item.kindRaw), item.kind != nil else { return false }
            if let expires = item.expiresAt, expires <= now { return false }
            return true
        }
        .sorted { lhs, rhs in
            let ls = Self.score(item: lhs, tokens: tokens)
            let rs = Self.score(item: rhs, tokens: tokens)
            if ls != rs { return ls > rs }
            if lhs.importance != rhs.importance { return lhs.importance > rhs.importance }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.confidence > rhs.confidence
        }
    }

    func upsertDebug(_ item: MemoryItem) throws {
        guard !item.profileId.isEmpty else { throw StoreError.invalidInput }
        let pid = item.profileId
        let key = item.key
        let existing = try context.fetch(
            FetchDescriptor<MemoryItem>(
                predicate: #Predicate {
                    $0.profileId == pid && $0.key == key && $0.deletedAt == nil
                }
            )
        ).first
        if let existing {
            existing.kindRaw = item.kindRaw
            existing.summaryText = item.summaryText
            existing.valueJSON = item.valueJSON
            existing.sourceType = item.sourceType
            existing.sourceId = item.sourceId
            existing.confidence = item.confidence
            existing.importance = item.importance
            existing.expiresAt = item.expiresAt
            existing.updatedAt = Date()
            existing.schemaVersion = item.schemaVersion
        } else {
            context.insert(item)
        }
    }

    func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    private static func score(item: MemoryItem, tokens: [String]) -> Int {
        guard !tokens.isEmpty else { return 0 }
        let hay = (item.key + " " + item.summaryText).lowercased()
        return tokens.contains { hay.contains($0) } ? 2 : 0
    }
}
