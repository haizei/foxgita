import Foundation
import SwiftData

@Observable
@MainActor
final class AIInvocationStore {
    @ObservationIgnored private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func record(_ input: AIInvocationRecordInput, now: Date = Date()) {
        do {
            guard let profileId = try activeProfileId(), !profileId.isEmpty else { return }
            let invocationId = input.id
            let existing = try context.fetch(
                FetchDescriptor<AIInvocationLog>(predicate: #Predicate { $0.id == invocationId })
            )
            if !existing.isEmpty { return }
            context.insert(AIInvocationLog(
                id: input.id,
                profileId: profileId,
                skillId: input.skillId,
                skillVersion: input.skillVersion,
                model: input.model,
                startedAt: input.startedAt,
                durationMs: input.durationMs,
                statusRaw: input.status.rawValue,
                errorTypeRaw: input.errorType?.rawValue ?? "",
                memoryIdsRaw: input.memoryIds.joined(separator: ","),
                formatRetryUsed: input.formatRetryUsed,
                draftOutcomeRaw: input.draftOutcome?.rawValue ?? "",
                now: now
            ))
            try context.save()
            try prune(profileId: profileId)
        } catch {
            return
        }
    }

    func setDraftOutcome(id: String, outcome: AIDraftOutcome, taskId: String?, now: Date = Date()) {
        do {
            let rows = try context.fetch(
                FetchDescriptor<AIInvocationLog>(predicate: #Predicate { $0.id == id })
            )
            guard let row = rows.first else { return }
            row.draftOutcomeRaw = outcome.rawValue
            if let taskId {
                row.taskId = taskId
            }
            row.updatedAt = now
            try context.save()
        } catch {
            return
        }
    }

    func markCompleted(taskId: String, now: Date) {
        do {
            let rows = try context.fetch(
                FetchDescriptor<AIInvocationLog>(
                    predicate: #Predicate { $0.taskId == taskId && $0.completedAt == nil }
                )
            )
            guard let row = rows.first else { return }
            row.completedAt = now
            try context.save()
        } catch {
            return
        }
    }

    func recent(limit: Int = 200) -> [AIInvocationLog] {
        do {
            guard let profileId = try activeProfileId(), !profileId.isEmpty else { return [] }
            var descriptor = FetchDescriptor<AIInvocationLog>(
                predicate: #Predicate { $0.profileId == profileId },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor)
        } catch {
            return []
        }
    }

    static func errorType(from error: Error) -> AIInvocationErrorType {
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError, urlError.code == .cancelled { return .cancelled }
        guard let vision = error as? VisionPracticeError else { return .transport }
        switch vision {
        case .invalidURL: return .invalidURL
        case .unauthorized: return .unauthorized
        case .httpStatus: return .httpStatus
        case .emptyContent: return .emptyContent
        case .invalidJSON: return .invalidJSON
        case .timeout: return .timeout
        case .transport: return .transport
        case .unregisteredSkill: return .unregisteredSkill
        }
    }

    static func debugBlob(of log: AIInvocationLog) -> String {
        [
            log.id,
            log.profileId,
            log.skillId,
            log.skillVersion,
            log.model,
            log.statusRaw,
            log.errorTypeRaw,
            log.memoryIdsRaw,
            log.draftOutcomeRaw,
            log.taskId,
        ].joined(separator: " ")
    }

    private func activeProfileId() throws -> String? {
        try context.fetch(
            FetchDescriptor<LocalProfile>(predicate: #Predicate { $0.isActive == true })
        ).first?.id
    }

    private func prune(profileId: String) throws {
        let rows = try context.fetch(
            FetchDescriptor<AIInvocationLog>(
                predicate: #Predicate { $0.profileId == profileId },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        )
        guard rows.count > 200 else { return }
        for row in rows.dropFirst(200) {
            context.delete(row)
        }
        try context.save()
    }
}

@MainActor
final class LiveAIInvocationLog: AIInvocationRecording {
    private let store: AIInvocationStore

    init(store: AIInvocationStore) {
        self.store = store
    }

    func record(_ input: AIInvocationRecordInput) async {
        store.record(input)
    }
}
