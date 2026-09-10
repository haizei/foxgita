import Foundation

struct VersionedToolSchema: Equatable, Sendable {
    let id: String
    let version: String
    let json: String
}

struct PromptAssembly: Sendable {
    let orderedTools: [VersionedToolSchema]
    let staticSystem: String
    let dynamicContext: String
    let history: [String]
    let currentInput: String
    let toolsetFingerprint: String
    let staticPromptFingerprint: String
    let historyPrefixFingerprint: String
    let contextFingerprint: String
}
