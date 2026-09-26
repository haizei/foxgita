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
            guard let safeID = Self.safeIdentifier(input.id),
                  let safeSkillID = Self.safeIdentifier(input.skillId),
                  let safeSkillVersion = Self.safeIdentifier(input.skillVersion) else { return }
            let invocationId = input.id
            let existing = try context.fetch(
                FetchDescriptor<AIInvocationLog>(predicate: #Predicate { $0.id == invocationId })
            )
            if !existing.isEmpty { return }
            context.insert(AIInvocationLog(
                id: safeID,
                profileId: profileId,
                sessionId: Self.safeMetadata(input.sessionID),
                skillId: safeSkillID,
                skillVersion: safeSkillVersion,
                runtime: Self.safeMetadata(input.runtime),
                model: Self.safeMetadata(input.model) ?? "redacted",
                executionStateRaw: input.executionState?.rawValue,
                startedAt: input.startedAt,
                durationMs: input.durationMs,
                statusRaw: input.status.rawValue,
                errorTypeRaw: input.errorType?.rawValue ?? "",
                refusalTypeRaw: Self.safeMetadata(input.refusalType),
                memoryIdsRaw: input.memoryIds.compactMap(Self.safeIdentifier).joined(separator: ","),
                staticPromptFingerprint: Self.safeMetadata(input.staticPromptFingerprint),
                historyPrefixFingerprint: Self.safeMetadata(input.historyPrefixFingerprint),
                contextFingerprint: Self.safeMetadata(input.contextFingerprint),
                toolsetFingerprint: Self.safeMetadata(input.toolsetFingerprint),
                inputTokens: input.usage?.inputTokens,
                outputTokens: input.usage?.outputTokens,
                cacheWriteTokens: input.usage?.cacheWriteTokens,
                cacheReadTokens: input.usage?.cacheReadTokens,
                imagePreparationMs: input.performance?.imagePreparationMs,
                preparedImageBytes: input.performance?.preparedImageBytes,
                preparedImageCount: input.performance?.preparedImageCount,
                modelWaitMs: input.performance?.modelWaitMs,
                firstResponseMs: input.performance?.firstResponseMs,
                imageSourceKindRaw: Self.safeMetadata(input.performance?.imageSourceKind),
                formatRetryUsed: input.formatRetryUsed,
                fallbackUsed: input.fallbackUsed,
                draftOutcomeRaw: (input.draftOutcome ?? (input.status == .failure ? .failed : nil))?.rawValue ?? "",
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
                guard let safeTaskID = Self.safeIdentifier(taskId) else { return }
                row.taskId = safeTaskID
                row.businessObjectId = safeTaskID
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
            row.businessObjectCompletedAt = now
            row.updatedAt = now
            try context.save()
        } catch {
            return
        }
    }

    func markArtifact(invocationID: String, artifactID: String, contextSnapshotID: String) {
        guard let artifactID = Self.safeIdentifier(artifactID),
              let contextSnapshotID = Self.safeIdentifier(contextSnapshotID) else { return }
        update(invocationID: invocationID) { row in
            guard row.artifactId == nil else { return }
            row.artifactId = artifactID
            row.contextSnapshotId = contextSnapshotID
        }
    }

    func markBusinessObject(invocationID: String, businessObjectID: String) {
        guard let businessObjectID = Self.safeIdentifier(businessObjectID) else { return }
        update(invocationID: invocationID) { row in
            guard row.businessObjectId == nil else { return }
            row.businessObjectId = businessObjectID
        }
    }

    func markStarted(invocationID: String, at: Date) {
        update(invocationID: invocationID) { row in
            guard row.businessObjectStartedAt == nil else { return }
            row.businessObjectStartedAt = at
        }
    }

    func markCompleted(invocationID: String, at: Date) {
        update(invocationID: invocationID) { row in
            guard row.businessObjectCompletedAt == nil else { return }
            row.businessObjectCompletedAt = at
            row.completedAt = at
            row.executionState = AIExecutionState.completed.rawValue
        }
    }

    func markRegenerated(invocationID: String, successorInvocationID: String, now: Date = Date()) {
        do {
            guard invocationID != successorInvocationID else { return }
            let invocationId = invocationID
            let successorId = successorInvocationID
            let predecessors = try context.fetch(
                FetchDescriptor<AIInvocationLog>(predicate: #Predicate { $0.id == invocationId })
            )
            let successors = try context.fetch(
                FetchDescriptor<AIInvocationLog>(predicate: #Predicate { $0.id == successorId })
            )
            guard let predecessor = predecessors.first, let successor = successors.first else { return }
            guard predecessor.successorInvocationId == nil, successor.predecessorInvocationId == nil else { return }
            predecessor.draftOutcomeRaw = AIDraftOutcome.regenerated.rawValue
            predecessor.successorInvocationId = successorInvocationID
            predecessor.updatedAt = now
            successor.predecessorInvocationId = invocationID
            successor.updatedAt = now
            try context.save()
        } catch {
            return
        }
    }

    func markPerformance(invocationID: String, performance: AIInvocationPerformance) {
        update(invocationID: invocationID) { row in
            row.imagePreparationMs = performance.imagePreparationMs
            row.preparedImageBytes = performance.preparedImageBytes
            row.preparedImageCount = performance.preparedImageCount
            row.modelWaitMs = performance.modelWaitMs
            row.firstResponseMs = performance.firstResponseMs
            row.imageSourceKindRaw = Self.safeMetadata(performance.imageSourceKind)
        }
    }

    func latestInvocationID(businessObjectID: String, skillID: String) -> String? {
        do {
            guard let profileID = try activeProfileId(), !profileID.isEmpty else { return nil }
            var descriptor = FetchDescriptor<AIInvocationLog>(
                predicate: #Predicate {
                    $0.profileId == profileID
                        && $0.businessObjectId == businessObjectID
                        && $0.skillId == skillID
                },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first?.id
        } catch {
            return nil
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
            log.refusalTypeRaw ?? "",
            log.memoryIdsRaw,
            log.runtime ?? "",
            log.executionState ?? "",
            log.sessionId ?? "",
            log.staticPromptFingerprint ?? "",
            log.historyPrefixFingerprint ?? "",
            log.contextFingerprint ?? "",
            log.toolsetFingerprint ?? "",
            log.artifactId ?? "",
            log.contextSnapshotId ?? "",
            log.businessObjectId ?? "",
            log.predecessorInvocationId ?? "",
            log.successorInvocationId ?? "",
            log.draftOutcomeRaw,
            log.taskId,
        ].joined(separator: " ")
    }

    private func activeProfileId() throws -> String? {
        try context.fetch(
            FetchDescriptor<LocalProfile>(predicate: #Predicate { $0.isActive == true })
        ).first?.id
    }

    private func update(invocationID: String, mutation: (AIInvocationLog) -> Void) {
        do {
            let rows = try context.fetch(
                FetchDescriptor<AIInvocationLog>(predicate: #Predicate { $0.id == invocationID })
            )
            guard let row = rows.first else { return }
            mutation(row)
            row.updatedAt = Date()
            try context.save()
        } catch {
            return
        }
    }

    private static func safeMetadata(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard value.count <= 256,
              !value.localizedCaseInsensitiveContains("bearer "),
              !value.localizedCaseInsensitiveContains("authorization"),
              !value.localizedCaseInsensitiveContains("file:"),
              !containsCredentialPrefix(value),
              !value.hasPrefix("/"),
              !value.contains("\\Users\\") else {
            return "redacted"
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:/-"))
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return "redacted" }
        return value
    }

    private static func safeIdentifier(_ value: String) -> String? {
        guard let safe = safeMetadata(value), safe != "redacted" else { return nil }
        return safe
    }

    private static func containsCredentialPrefix(_ value: String) -> Bool {
        let value = value.lowercased()
        var searchStart = value.startIndex
        while let range = value.range(of: "sk-", range: searchStart..<value.endIndex) {
            if range.lowerBound == value.startIndex { return true }
            let previous = value[value.index(before: range.lowerBound)]
            if !previous.isLetter && !previous.isNumber { return true }
            searchStart = range.upperBound
        }
        return false
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

    func linkArtifact(invocationID: String, artifactID: String, contextSnapshotID: String) async {
        store.markArtifact(
            invocationID: invocationID,
            artifactID: artifactID,
            contextSnapshotID: contextSnapshotID
        )
    }

    func recordPerformance(invocationID: String, performance: AIInvocationPerformance) async {
        store.markPerformance(invocationID: invocationID, performance: performance)
    }
}
