import Foundation
import SwiftData

@MainActor
final class TaskMemorySync {
    private(set) var lastError: StoreError?

    private let repository: MemoryRepository
    private let context: ModelContext

    init(repository: MemoryRepository, context: ModelContext) {
        self.repository = repository
        self.context = context
    }

    func syncUpsert(task: TaskItem) {
        lastError = nil
        guard task.id.hasPrefix("custom-"),
              task.deletedAt == nil,
              !task.profileId.isEmpty,
              consent(for: task.profileId) == .enabled
        else { return }
        do {
            try repository.upsertTaskGoal(
                profileId: task.profileId, taskId: task.id, title: task.title
            )
            try repository.save()
        } catch {
            lastError = StoreError.from(error)
        }
    }

    func syncDelete(taskId: String, profileId: String) {
        lastError = nil
        guard taskId.hasPrefix("custom-"), !profileId.isEmpty else { return }
        do {
            try repository.softDeleteTaskGoal(profileId: profileId, taskId: taskId)
            try repository.save()
        } catch {
            lastError = StoreError.from(error)
        }
    }

    func backfill(profileId: String) {
        lastError = nil
        guard !profileId.isEmpty, consent(for: profileId) == .enabled else { return }
        let pid = profileId
        do {
            let tasks = try context.fetch(
                FetchDescriptor<TaskItem>(
                    predicate: #Predicate { $0.profileId == pid && $0.deletedAt == nil }
                )
            )
            for task in tasks where task.id.hasPrefix("custom-") {
                do {
                    try repository.upsertTaskGoal(
                        profileId: pid, taskId: task.id, title: task.title
                    )
                } catch let error as StoreError where error == .invalidInput {
                    continue
                } catch {
                    lastError = StoreError.from(error)
                    continue
                }
            }
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
