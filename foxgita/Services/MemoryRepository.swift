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
    func upsertUser(profileId: String, kind: MemoryScope, summaryText: String) throws -> MemoryItem
    func updateSummary(profileId: String, id: String, summaryText: String) throws
    func softDelete(profileId: String, id: String) throws
    func softDeleteAll(profileId: String) throws
    func setConsent(profileId: String, _ state: MemoryConsentState) throws
    func upsertTaskGoal(profileId: String, taskId: String, title: String) throws
    func softDeleteTaskGoal(profileId: String, taskId: String) throws
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

    private func normalizedSummary(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 120 else { throw StoreError.invalidInput }
        return text
    }

    func upsertUser(profileId: String, kind: MemoryScope, summaryText: String) throws -> MemoryItem {
        guard !profileId.isEmpty else { throw StoreError.invalidInput }
        guard kind == .goal || kind == .preference else { throw StoreError.invalidInput }
        let summary = try normalizedSummary(summaryText)
        let item = MemoryItem(
            profileId: profileId,
            kind: kind,
            key: "user.\(kind.rawValue).\(UUID().uuidString)",
            summaryText: summary,
            sourceType: "user",
            sourceId: "",
            confidence: 1,
            importance: 0.8
        )
        context.insert(item)
        return item
    }

    func updateSummary(profileId: String, id: String, summaryText: String) throws {
        guard !profileId.isEmpty, !id.isEmpty else { throw StoreError.invalidInput }
        let summary = try normalizedSummary(summaryText)
        let pid = profileId
        let itemId = id
        guard let item = try context.fetch(
            FetchDescriptor<MemoryItem>(
                predicate: #Predicate { $0.profileId == pid && $0.id == itemId && $0.deletedAt == nil }
            )
        ).first else { throw StoreError.invalidInput }
        item.summaryText = summary
        if item.sourceType == "task" {
            item.sourceType = "user"
        }
        item.updatedAt = Date()
    }

    func softDelete(profileId: String, id: String) throws {
        guard !profileId.isEmpty, !id.isEmpty else { throw StoreError.invalidInput }
        let pid = profileId
        let itemId = id
        guard let item = try context.fetch(
            FetchDescriptor<MemoryItem>(
                predicate: #Predicate { $0.profileId == pid && $0.id == itemId && $0.deletedAt == nil }
            )
        ).first else { return }
        item.deletedAt = Date()
        item.updatedAt = Date()
    }

    func softDeleteAll(profileId: String) throws {
        guard !profileId.isEmpty else { throw StoreError.invalidInput }
        let pid = profileId
        let rows = try context.fetch(
            FetchDescriptor<MemoryItem>(
                predicate: #Predicate { $0.profileId == pid && $0.deletedAt == nil }
            )
        )
        let now = Date()
        for row in rows {
            row.deletedAt = now
            row.updatedAt = now
        }
    }

    func setConsent(profileId: String, _ state: MemoryConsentState) throws {
        guard !profileId.isEmpty else { throw StoreError.invalidInput }
        let pid = profileId
        guard let profile = try context.fetch(
            FetchDescriptor<LocalProfile>(predicate: #Predicate { $0.id == pid })
        ).first else { throw StoreError.invalidInput }
        profile.consent = state
    }

    private func taskGoalKey(_ taskId: String) -> String {
        "task.\(taskId).title"
    }

    private func taskGoalRows(profileId: String, taskId: String) throws -> [MemoryItem] {
        let pid = profileId
        let key = taskGoalKey(taskId)
        return try context.fetch(
            FetchDescriptor<MemoryItem>(
                predicate: #Predicate { $0.profileId == pid && $0.key == key }
            )
        )
    }

    func upsertTaskGoal(profileId: String, taskId: String, title: String) throws {
        guard !profileId.isEmpty, !taskId.isEmpty else { throw StoreError.invalidInput }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let summary = trimmed.count <= 120 ? trimmed : String(trimmed.prefix(120))
        let rows = try taskGoalRows(profileId: profileId, taskId: taskId)
        if rows.contains(where: { $0.deletedAt != nil }) { return }
        if let live = rows.first(where: { $0.deletedAt == nil }) {
            guard live.sourceType == "task" else { return }
            live.summaryText = summary
            live.updatedAt = Date()
            return
        }
        context.insert(
            MemoryItem(
                profileId: profileId,
                kind: .goal,
                key: taskGoalKey(taskId),
                summaryText: summary,
                sourceType: "task",
                sourceId: taskId,
                confidence: 1,
                importance: 0.6
            )
        )
    }

    func softDeleteTaskGoal(profileId: String, taskId: String) throws {
        guard !profileId.isEmpty, !taskId.isEmpty else { throw StoreError.invalidInput }
        let live = try taskGoalRows(profileId: profileId, taskId: taskId)
            .first { $0.deletedAt == nil && $0.sourceType == "task" }
        guard let live else { return }
        let now = Date()
        live.deletedAt = now
        live.updatedAt = now
    }

    private static func score(item: MemoryItem, tokens: [String]) -> Int {
        guard !tokens.isEmpty else { return 0 }
        let hay = (item.key + " " + item.summaryText).lowercased()
        return tokens.contains { hay.contains($0) } ? 2 : 0
    }
}
