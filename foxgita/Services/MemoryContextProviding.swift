import Foundation
import SwiftData
import SwiftUI

struct MemoryPromptSnapshot: Equatable, Sendable {
    var block: String
    var itemIds: [String]
}

protocol MemoryContextProviding: Sendable {
    func block(skill: SkillDefinition, query: String) async -> String
    func snapshot(skill: SkillDefinition, query: String) async -> MemoryPromptSnapshot
}

extension MemoryContextProviding {
    func snapshot(skill: SkillDefinition, query: String) async -> MemoryPromptSnapshot {
        MemoryPromptSnapshot(block: await block(skill: skill, query: query), itemIds: [])
    }
}

struct EmptyMemoryContext: MemoryContextProviding {
    func block(skill: SkillDefinition, query: String) async -> String { "" }
    func snapshot(skill: SkillDefinition, query: String) async -> MemoryPromptSnapshot {
        MemoryPromptSnapshot(block: "", itemIds: [])
    }
}

@MainActor
final class LiveMemoryContext: MemoryContextProviding {
    private let repository: MemoryRepository
    private let context: ModelContext

    init(repository: MemoryRepository, context: ModelContext) {
        self.repository = repository
        self.context = context
    }

    nonisolated func block(skill: SkillDefinition, query: String) async -> String {
        await snapshot(skill: skill, query: query).block
    }

    nonisolated func snapshot(skill: SkillDefinition, query: String) async -> MemoryPromptSnapshot {
        await MainActor.run { [self] in
            self.build(skill: skill, query: query)
        }
    }

    private func build(skill: SkillDefinition, query: String) -> MemoryPromptSnapshot {
        guard !skill.memoryReadScopes.isEmpty else { return MemoryPromptSnapshot(block: "", itemIds: []) }
        do {
            let profile = try context.fetch(
                FetchDescriptor<LocalProfile>(
                    predicate: #Predicate { $0.isActive == true }
                )
            ).first
            guard let profile, profile.consent == .enabled else { return MemoryPromptSnapshot(block: "", itemIds: []) }
            let items = try repository.fetch(
                profileId: profile.id,
                scopes: skill.memoryReadScopes,
                matching: query,
                now: Date()
            )
            return MemoryContextBuilder.snapshot(items: items, now: Date())
        } catch {
            return MemoryPromptSnapshot(block: "", itemIds: [])
        }
    }
}

private struct MemoryContextKey: EnvironmentKey {
    static let defaultValue: any MemoryContextProviding = EmptyMemoryContext()
}

extension EnvironmentValues {
    var memoryContext: any MemoryContextProviding {
        get { self[MemoryContextKey.self] }
        set { self[MemoryContextKey.self] = newValue }
    }
}
