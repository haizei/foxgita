import Foundation

enum AIInvocationStatus: String, Sendable { case success, failure }

enum AIInvocationErrorType: String, Sendable {
    case notConfigured, invalidURL, unauthorized, httpStatus
    case emptyContent, invalidJSON, timeout, transport
    case unregisteredSkill, cancelled
}

enum AIDraftOutcome: String, Sendable {
    case accepted, edited, regenerated, abandoned
}

struct AIInvocationRecordInput: Equatable, Sendable {
    var id: String
    var skillId: String
    var skillVersion: String
    var model: String
    var startedAt: Date
    var durationMs: Int
    var status: AIInvocationStatus
    var errorType: AIInvocationErrorType?
    var memoryIds: [String]
    var formatRetryUsed: Bool
    var draftOutcome: AIDraftOutcome?
}

protocol AIInvocationRecording: Sendable {
    func record(_ input: AIInvocationRecordInput) async
}

struct EmptyAIInvocationLog: AIInvocationRecording {
    func record(_ input: AIInvocationRecordInput) async {}
}

enum AIInvocationClientRecord {
    static func make(
        id: String,
        skill: SkillDefinition,
        model: String,
        startedAt: Date,
        status: AIInvocationStatus,
        error: Error?,
        memoryIds: [String],
        formatRetryUsed: Bool
    ) -> AIInvocationRecordInput {
        let cancelled = error.map { AIInvocationStore.errorType(from: $0) } == .cancelled
        let practiceSkill = skill.id == SkillID.nextSession || skill.id == SkillID.planFromImage
        return AIInvocationRecordInput(
            id: id,
            skillId: skill.id,
            skillVersion: skill.version,
            model: model,
            startedAt: startedAt,
            durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1000)),
            status: status,
            errorType: error.map(AIInvocationStore.errorType(from:)),
            memoryIds: memoryIds,
            formatRetryUsed: formatRetryUsed,
            draftOutcome: (cancelled && practiceSkill) ? .abandoned : nil
        )
    }

    static func thrownError(from error: Error) -> Error {
        if error is CancellationError { return error }
        if AIInvocationStore.errorType(from: error) == .cancelled { return error }
        if let vision = error as? VisionPracticeError { return vision }
        if (error as? URLError)?.code == .timedOut { return VisionPracticeError.timeout }
        return VisionPracticeError.transport
    }
}
