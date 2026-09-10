import Foundation

enum PromptAssembler {
    static func assemble(
        tools: [VersionedToolSchema],
        staticSystem: String,
        dynamicContext: String,
        history: [String],
        currentInput: String
    ) -> PromptAssembly {
        let orderedTools = tools.map(canonicalize).sorted(by: toolOrder)
        let toolsetBytes = PromptFingerprint.frame(orderedTools.map(serialize))
        let staticPrefixBytes = PromptFingerprint.frame([toolsetBytes, staticSystem])
        let historyPrefixBytes = PromptFingerprint.frame([staticPrefixBytes, dynamicContext, PromptFingerprint.frame(history)])

        return PromptAssembly(
            orderedTools: orderedTools,
            staticSystem: staticSystem,
            dynamicContext: dynamicContext,
            history: history,
            currentInput: currentInput,
            toolsetFingerprint: PromptFingerprint.sha256(toolsetBytes),
            staticPromptFingerprint: PromptFingerprint.sha256(staticPrefixBytes),
            historyPrefixFingerprint: PromptFingerprint.sha256(historyPrefixBytes),
            contextFingerprint: PromptFingerprint.sha256(dynamicContext)
        )
    }

    private static func toolOrder(_ lhs: VersionedToolSchema, _ rhs: VersionedToolSchema) -> Bool {
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        if lhs.version != rhs.version { return lhs.version < rhs.version }
        return PromptFingerprint.canonicalJSON(lhs.json) < PromptFingerprint.canonicalJSON(rhs.json)
    }

    private static func serialize(_ tool: VersionedToolSchema) -> String {
        PromptFingerprint.frame([tool.id, tool.version, tool.json])
    }

    private static func canonicalize(_ tool: VersionedToolSchema) -> VersionedToolSchema {
        VersionedToolSchema(
            id: tool.id,
            version: tool.version,
            json: PromptFingerprint.canonicalJSON(tool.json)
        )
    }
}
