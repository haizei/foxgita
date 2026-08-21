import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class MemoryStore {
    private let repository: MemoryRepository
    private let context: ModelContext

    private(set) var consent: MemoryConsentState = .undecided
    private(set) var items: [MemoryItem] = []
    private(set) var lastError: StoreError?

    init(repository: MemoryRepository, context: ModelContext) {
        self.repository = repository
        self.context = context
    }

    func reload() {
        do {
            lastError = nil
            let profile = try activeProfile()
            consent = profile?.consent ?? .undecided
            guard let id = profile?.id, !id.isEmpty else {
                items = []
                return
            }
            items = try repository.fetch(
                profileId: id,
                scopes: [.goal, .preference, .ability, .fact, .summary],
                matching: "",
                now: Date()
            )
        } catch {
            lastError = StoreError.from(error)
            items = []
        }
    }

    @discardableResult
    func setConsent(_ state: MemoryConsentState) -> Bool {
        mutate { profileId in
            try repository.setConsent(profileId: profileId, state)
        }
    }

    @discardableResult
    func add(kind: MemoryScope, summary: String) -> Bool {
        guard consent == .enabled else {
            lastError = .invalidInput
            return false
        }
        return mutate { profileId in
            _ = try repository.upsertUser(profileId: profileId, kind: kind, summaryText: summary)
        }
    }

    @discardableResult
    func updateSummary(id: String, summary: String) -> Bool {
        mutate { profileId in
            try repository.updateSummary(profileId: profileId, id: id, summaryText: summary)
        }
    }

    @discardableResult
    func delete(id: String) -> Bool {
        mutate { profileId in
            try repository.softDelete(profileId: profileId, id: id)
        }
    }

    @discardableResult
    func clearAll() -> Bool {
        mutate { profileId in
            try repository.softDeleteAll(profileId: profileId)
        }
    }

    private func mutate(_ work: (String) throws -> Void) -> Bool {
        do {
            guard let id = try activeProfile()?.id, !id.isEmpty else {
                lastError = .invalidInput
                return false
            }
            try work(id)
            try repository.save()
            reload()
            return lastError == nil
        } catch {
            lastError = StoreError.from(error)
            return false
        }
    }

    private func activeProfile() throws -> LocalProfile? {
        try context.fetch(
            FetchDescriptor<LocalProfile>(predicate: #Predicate { $0.isActive == true })
        ).first
    }
}
