import Foundation
import SwiftData

@MainActor
final class AICandidateSync {
    private(set) var lastError: StoreError?

    private let repository: MemoryRepository
    private let context: ModelContext

    init(repository: MemoryRepository, context: ModelContext) {
        self.repository = repository
        self.context = context
    }

    func syncFocus(
        profileId: String,
        focus: String,
        recordingId: String,
        skill: SkillDefinition
    ) {
        lastError = nil
        guard !profileId.isEmpty,
              skill.memoryWritePolicy == .candidates,
              consent(for: profileId) == .enabled
        else { return }
        do {
            try repository.upsertAICandidate(
                profileId: profileId,
                recordingId: recordingId,
                summaryText: focus,
                valueJSON: "\(skill.id)@\(skill.version)"
            )
            try repository.save()
        } catch {
            lastError = StoreError.from(error)
        }
    }

    private func consent(for profileId: String) -> MemoryConsentState? {
        let pid = profileId
        let profile = try? context.fetch(
            FetchDescriptor<LocalProfile>(predicate: #Predicate { $0.id == pid })
        ).first
        return profile?.consent
    }
}
