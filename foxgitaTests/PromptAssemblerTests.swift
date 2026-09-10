import Foundation
import Testing
@testable import foxgita

struct PromptAssemblerTests {
    @Test func toolOrderDoesNotChangeBP1Fingerprint() throws {
        let a = VersionedToolSchema(id: "b", version: "1", json: #"{"type":"object"}"#)
        let b = VersionedToolSchema(id: "a", version: "1", json: #"{"type":"object"}"#)
        let first = PromptAssembler.assemble(
            tools: [a, b],
            staticSystem: "stable",
            dynamicContext: "project one",
            history: [],
            currentInput: "go"
        )
        let second = PromptAssembler.assemble(
            tools: [b, a],
            staticSystem: "stable",
            dynamicContext: "project two",
            history: [],
            currentInput: "go"
        )

        #expect(first.toolsetFingerprint == second.toolsetFingerprint)
        #expect(first.staticPromptFingerprint == second.staticPromptFingerprint)
        #expect(first.contextFingerprint != second.contextFingerprint)
    }

    @Test func dynamicDataNeverAppearsInStaticSystem() {
        let result = PromptAssembler.assemble(
            tools: [],
            staticSystem: "core-v1",
            dynamicContext: "Project Alice 09:31",
            history: [],
            currentInput: "hello"
        )

        #expect(result.staticSystem == "core-v1")
        #expect(!result.staticSystem.contains("Alice"))
    }

    @Test func equivalentJSONSchemaKeyOrderProducesSameBP1AndBP2Fingerprints() {
        let first = PromptAssembler.assemble(
            tools: [VersionedToolSchema(id: "task.read", version: "1", json: #"{"b":2,"a":1}"#)],
            staticSystem: "core-v1",
            dynamicContext: "project one",
            history: [],
            currentInput: "go"
        )
        let second = PromptAssembler.assemble(
            tools: [VersionedToolSchema(id: "task.read", version: "1", json: #"{"a":1,"b":2}"#)],
            staticSystem: "core-v1",
            dynamicContext: "project one",
            history: [],
            currentInput: "go"
        )

        #expect(first.toolsetFingerprint == second.toolsetFingerprint)
        #expect(first.staticPromptFingerprint == second.staticPromptFingerprint)
        #expect(first.orderedTools == second.orderedTools)
    }

    @Test func laterLayersDoNotInvalidateEarlierBreakpoints() {
        let tool = VersionedToolSchema(id: "task.read", version: "1", json: #"{"type":"object"}"#)
        let baseline = PromptAssembler.assemble(
            tools: [tool],
            staticSystem: "core-v1",
            dynamicContext: "project one",
            history: ["first message"],
            currentInput: "go"
        )
        let changedDynamic = PromptAssembler.assemble(
            tools: [tool],
            staticSystem: "core-v1",
            dynamicContext: "project two with memory and consent",
            history: ["first message"],
            currentInput: "go"
        )
        let changedHistoryAndInput = PromptAssembler.assemble(
            tools: [tool],
            staticSystem: "core-v1",
            dynamicContext: "project one",
            history: ["second message"],
            currentInput: "new input"
        )

        #expect(baseline.toolsetFingerprint == changedDynamic.toolsetFingerprint)
        #expect(baseline.staticPromptFingerprint == changedDynamic.staticPromptFingerprint)
        #expect(baseline.contextFingerprint != changedDynamic.contextFingerprint)
        #expect(baseline.historyPrefixFingerprint != changedDynamic.historyPrefixFingerprint)

        #expect(baseline.toolsetFingerprint == changedHistoryAndInput.toolsetFingerprint)
        #expect(baseline.staticPromptFingerprint == changedHistoryAndInput.staticPromptFingerprint)
        #expect(baseline.contextFingerprint == changedHistoryAndInput.contextFingerprint)
        #expect(baseline.historyPrefixFingerprint != changedHistoryAndInput.historyPrefixFingerprint)
    }

    @Test func orderedToolsSortByIDThenVersion() {
        let result = PromptAssembler.assemble(
            tools: [
                VersionedToolSchema(id: "b", version: "1", json: "{}"),
                VersionedToolSchema(id: "a", version: "2", json: "{}"),
                VersionedToolSchema(id: "a", version: "1", json: "{}")
            ],
            staticSystem: "core-v1",
            dynamicContext: "",
            history: [],
            currentInput: ""
        )

        #expect(result.orderedTools.map { "\($0.id)@\($0.version)" } == ["a@1", "a@2", "b@1"])
    }
}
