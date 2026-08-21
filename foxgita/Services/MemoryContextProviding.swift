import Foundation
import SwiftData
import SwiftUI

protocol MemoryContextProviding: Sendable {
    func block(skill: SkillDefinition, query: String) async -> String
}

struct EmptyMemoryContext: MemoryContextProviding {
    func block(skill: SkillDefinition, query: String) async -> String { "" }
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
        await MainActor.run { [self] in
            self.build(skill: skill, query: query)
        }
    }

    private func build(skill: SkillDefinition, query: String) -> String {
        guard !skill.memoryReadScopes.isEmpty else { return "" }
        do {
            let profile = try context.fetch(
                FetchDescriptor<LocalProfile>(
                    predicate: #Predicate { $0.isActive == true }
                )
            ).first
            guard let profile, profile.memoryConsent else { return "" }
            let items = try repository.fetch(
                profileId: profile.id,
                scopes: skill.memoryReadScopes,
                matching: query,
                now: Date()
            )
            return MemoryContextBuilder.block(items: items, now: Date())
        } catch {
            return ""
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
