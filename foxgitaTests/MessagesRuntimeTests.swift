import Foundation
import Testing
@testable import foxgita

private struct RuntimeTransportStub: MessagesTransporting {
    let result: AITransportResult

    func complete(_ request: MessagesTransportRequest) async throws -> AITransportResult {
        result
    }
}

private struct UnauthorizedRuntimeTransportStub: MessagesTransporting {
    func complete(_ request: MessagesTransportRequest) async throws -> AITransportResult {
        throw VisionPracticeError.unauthorized
    }
}

private struct CancelledRuntimeTransportStub: MessagesTransporting {
    func complete(_ request: MessagesTransportRequest) async throws -> AITransportResult {
        throw CancellationError()
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

    @Test func mapsTransportFailureToNeutralFailureEvent() async throws {
        let events = try await RuntimeTestFixtures.collect(
            MessagesRuntime(transport: UnauthorizedRuntimeTransportStub()).execute(
                plan: RuntimeTestFixtures.plan,
                prompt: RuntimeTestFixtures.prompt,
                credentials: RuntimeTestFixtures.credentials
            )
        )

        #expect(events == [.accepted, .started, .failed(.unauthorized)])
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

    static let prompt = PromptAssembly(
        orderedTools: [],
        staticSystem: "system",
        dynamicContext: "context",
        history: ["history"],
        currentInput: "input",
        toolsetFingerprint: "tools",
        staticPromptFingerprint: "static",
        historyPrefixFingerprint: "history",
        contextFingerprint: "context"
    )

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
