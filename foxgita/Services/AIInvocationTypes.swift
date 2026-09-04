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
