import Foundation
import Testing
@testable import foxgita

private struct RuntimeTransportStub: MessagesTransporting {
    let result: AITransportResult

    func complete(_ request: MessagesTransportRequest) async throws -> AITransportResult {
        result
    }
}

private struct TypedRuntimeErrorTransportStub: MessagesTransporting {
    let error: AIRuntimeError

    func complete(_ request: MessagesTransportRequest) async throws -> AITransportResult {
        throw error
    }
}

private struct CancelledRuntimeTransportStub: MessagesTransporting {
    func complete(_ request: MessagesTransportRequest) async throws -> AITransportResult {
        throw CancellationError()
    }
}

private actor CapturingRuntimeTransport: MessagesTransporting {
    private var request: MessagesTransportRequest?

    func complete(_ request: MessagesTransportRequest) async throws -> AITransportResult {
        self.request = request
        return await MainActor.run {
            AITransportResult(content: "{}", formatRetryUsed: false)
        }
    }

    func receivedRequest() -> MessagesTransportRequest? {
        request
    }
}

struct MessagesRuntimeTests {
    @Test func aiTransportConformsToMessagesTransportBoundary() {
        let transport: any MessagesTransporting = AITransport()
        #expect(transport is AITransport)
    }

    @Test func emitsArtifactAndUsageWithoutDomainDecoding() async throws {
        let usage = RuntimeUsage(
            inputTokens: 20,
            outputTokens: 5,
            cacheWriteTokens: 0,
            cacheReadTokens: 12
        )
        let content = #"{"title":"Warm up"}"#
        let runtime = MessagesRuntime(
            transport: RuntimeTransportStub(
                result: AITransportResult(content: content, formatRetryUsed: false, usage: usage)
            )
        )

        let events = try await RuntimeTestFixtures.collect(
            runtime.execute(
                plan: RuntimeTestFixtures.plan,
                prompt: RuntimeTestFixtures.prompt,
                credentials: RuntimeTestFixtures.credentials
            )
        )

        #expect(events == [
            .accepted,
            .started,
            .artifactProduced(Data(content.utf8)),
            .completed(usage),
        ])
    }

    @Test func keepsOrderedToolsOutOfSystemPrompt() async throws {
        let tools = [
            VersionedToolSchema(id: "first", version: "1", json: #"{"type":"object"}"#),
            VersionedToolSchema(id: "second", version: "2", json: #"{"type":"object"}"#),
        ]
        let transport = CapturingRuntimeTransport()
        let runtime = MessagesRuntime(transport: transport)

        _ = try await RuntimeTestFixtures.collect(
            runtime.execute(
                plan: RuntimeTestFixtures.plan,
                prompt: RuntimeTestFixtures.prompt(withTools: tools),
                credentials: RuntimeTestFixtures.credentials
            )
        )

        let request = await transport.receivedRequest()
        #expect(request?.systemPrompt == "system")
        #expect(request?.orderedTools.map(\.id) == ["first", "second"])
    }

    @Test func forwardsInvocationMediaSeparatelyFromPromptText() async throws {
        let transport = CapturingRuntimeTransport()
        let runtime = MessagesRuntime(transport: transport)
        let bytes = Data([0xFF, 0xD8, 0xFF])
        let ref = ResourceRef(kind: "image", id: "image-1")
        let plan = AgentExecutionPlan(
            invocationID: UUID(),
            sessionID: UUID(),
            recipe: RuntimeTestFixtures.plan.recipe,
            contextSnapshot: RuntimeTestFixtures.plan.contextSnapshot,
            seenSet: RuntimeTestFixtures.plan.seenSet,
            mediaResources: [InvocationMediaResource(ref: ref, mimeType: "image/jpeg", data: bytes)]
        )

        _ = try await RuntimeTestFixtures.collect(
            runtime.execute(plan: plan, prompt: RuntimeTestFixtures.prompt, credentials: RuntimeTestFixtures.credentials)
        )

        let request = await transport.receivedRequest()
        #expect(request?.imageJPEGData == [bytes])
        #expect(request?.userText.contains(bytes.base64EncodedString()) == false)
    }

    @Test func preservesTypedRuntimeErrorInFailureEvent() async throws {
        let events = try await RuntimeTestFixtures.collect(
            MessagesRuntime(transport: TypedRuntimeErrorTransportStub(error: .httpStatus(429))).execute(
                plan: RuntimeTestFixtures.plan,
                prompt: RuntimeTestFixtures.prompt,
                credentials: RuntimeTestFixtures.credentials
            )
        )

        #expect(events == [.accepted, .started, .failed(.httpStatus(429))])
    }

    @Test func mapsCancellationToCancelledEvent() async throws {
        let events = try await RuntimeTestFixtures.collect(
            MessagesRuntime(transport: CancelledRuntimeTransportStub()).execute(
                plan: RuntimeTestFixtures.plan,
                prompt: RuntimeTestFixtures.prompt,
                credentials: RuntimeTestFixtures.credentials
            )
        )

        #expect(events == [.accepted, .started, .cancelled])
    }
}

private enum RuntimeTestFixtures {
    static let plan = AgentExecutionPlan(
        invocationID: UUID(),
        sessionID: UUID(),
        recipe: RecipeDefinition(
            id: "runtime.fixture",
            family: "runtime",
            version: "1",
            title: "Runtime fixture",
            fetchPolicy: .empty,
            outputSchemaID: "fixture.v1",
            runtimeRequirements: .messagesOnly,
            approvalPolicy: .none,
            timeoutSeconds: 30,
            allowsFormatRepair: true
        ),
        contextSnapshot: ContextSnapshot(
            id: UUID(),
            createdAt: .distantPast,
            sections: [],
            warnings: [],
            revision: "fixture"
        ),
        seenSet: SeenSet(snapshotID: UUID(), resources: [])
    )

    static func prompt(withTools orderedTools: [VersionedToolSchema] = []) -> PromptAssembly {
        PromptAssembly(
            orderedTools: orderedTools,
            staticSystem: "system",
            dynamicContext: "context",
            history: ["history"],
            currentInput: "input",
            toolsetFingerprint: "tools",
            staticPromptFingerprint: "static",
            historyPrefixFingerprint: "history",
            contextFingerprint: "context"
        )
    }

    static let prompt = prompt()

    static let credentials = RuntimeCredentials(
        baseURL: "https://example.com/v1",
        apiKey: "key",
        model: "model"
    )

    static func collect(_ stream: AsyncThrowingStream<RuntimeEvent, Error>) async throws -> [RuntimeEvent] {
        var events: [RuntimeEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}
