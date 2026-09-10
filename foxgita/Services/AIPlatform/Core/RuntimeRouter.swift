import Foundation

struct RuntimeRouter: Sendable {
    let messages: any AgentRuntime

    func runtime(for requirements: RuntimeRequirements) throws -> any AgentRuntime {
        guard requirements.allowedKinds.contains(.messages), !requirements.requiresDurability else {
            throw AIRuntimeError.invalidResponse
        }
        return messages
    }
}
