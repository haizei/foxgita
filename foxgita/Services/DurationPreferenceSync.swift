import Foundation
import SwiftData
import SwiftUI

@MainActor
final class DurationPreferenceSync {
    private(set) var lastError: StoreError?

    private let repository: MemoryRepository
    private let context: ModelContext

    init(repository: MemoryRepository, context: ModelContext) {
        self.repository = repository
        self.context = context
    }

    func sync(profileId: String, minutes: Int) {
        lastError = nil
        guard !profileId.isEmpty, consent(for: profileId) == .enabled else { return }
        do {
            try repository.upsertDurationPreference(profileId: profileId, minutes: minutes)
            try repository.save()
        } catch {
            lastError = StoreError.from(error)
        }
    }

    func syncActive(minutes: Int) {
        lastError = nil
        let profile = try? context.fetch(
            FetchDescriptor<LocalProfile>(predicate: #Predicate { $0.isActive == true })
        ).first
        guard let id = profile?.id, !id.isEmpty else { return }
        sync(profileId: id, minutes: minutes)
    }

    private func consent(for profileId: String) -> MemoryConsentState? {
        let pid = profileId
        let profile = try? context.fetch(
            FetchDescriptor<LocalProfile>(predicate: #Predicate { $0.id == pid })
        ).first
        return profile?.consent
    }
}

private struct DurationPreferenceSyncKey: EnvironmentKey {
    static let defaultValue: DurationPreferenceSync? = nil
}

extension EnvironmentValues {
    var durationPreferenceSync: DurationPreferenceSync? {
        get { self[DurationPreferenceSyncKey.self] }
        set { self[DurationPreferenceSyncKey.self] = newValue }
    }
}
