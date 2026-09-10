import Foundation
import Testing
@testable import foxgita

struct AgentOrchestratorTests {
    @Test func runFreezesContextBeforeRuntimeAndReturnsValidatedArtifact() async throws {
        let fixture = OrchestratorFixture.success(payload: #"{"value":"ok"}"#)

        let result = try await fixture.orchestrator.run(request: fixture.request, credentials: .fixture)

        #expect(result.state == .presenting)
        #expect(result.artifact.contextSnapshotID == fixture.snapshot.id)
        #expect(fixture.runtime.receivedSnapshotIDs == [fixture.snapshot.id])
    }

    @Test func inputRefusalDoesNotExecuteRuntime() async {
        let fixture = OrchestratorFixture.inputRefused()

        await #expect(throws: GateRefusal.self) {
            try await fixture.orchestrator.run(request: fixture.request, credentials: .fixture)
        }
        #expect(fixture.runtime.executionCount == 0)
    }
}

private struct FrozenContextFixture: ContextSnapshotting {
    let snapshot: ContextSnapshot
    let seenSet: SeenSet

    func fetch(
        refs: [ResourceRef],
        policy: FetchPolicy,
        scope: ContextFetchScope
    ) async throws -> (ContextSnapshot, SeenSet) {
        (snapshot, seenSet)
    }
}

private final class RuntimeSpy: AgentRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private let payload: Data
    private var snapshotIDs: [UUID] = []

    init(payload: Data) {
        self.payload = payload
    }

    var receivedSnapshotIDs: [UUID] {
        lock.lock()
        defer { lock.unlock() }
        return snapshotIDs
    }

    var executionCount: Int {
        receivedSnapshotIDs.count
    }

    func execute(
        plan: AgentExecutionPlan,
        prompt: PromptAssembly,
        credentials: RuntimeCredentials
    ) -> AsyncThrowingStream<RuntimeEvent, Error> {
        lock.lock()
        snapshotIDs.append(plan.contextSnapshot.id)
        lock.unlock()

        return AsyncThrowingStream { continuation in
            continuation.yield(.accepted)
            continuation.yield(.started)
            continuation.yield(.artifactProduced(payload))
            continuation.yield(.completed(.zero))
            continuation.finish()
        }
    }
}

private struct FixtureExtension: AgentExtension {
    let recipe: RecipeDefinition
    let invocationID: UUID
    let snapshotID: UUID

    var id: String { "fixture" }
    var recipes: [RecipeDefinition] { [recipe] }

    func staticSystem(for recipe: RecipeDefinition) throws -> String {
        "fixture-system"
    }

    func decodeAndValidate(data: Data, recipe: RecipeDefinition, seenSet: SeenSet) throws -> AnySkillArtifact {
        AnySkillArtifact(
            id: UUID(),
            invocationID: invocationID,
            recipeID: recipe.id,
            recipeVersion: recipe.version,
            contextSnapshotID: snapshotID,
            payloadData: data,
            resourceRefs: [],
            requiresApproval: false
        )
    }
}

private struct RefusingInputGate: InputGating {
    func validate(
        request: InteractionRequest,
        recipe: RecipeDefinition,
        snapshot: ContextSnapshot,
        prompt: PromptAssembly
    ) throws {
        throw GateRefusal.constraintViolated("fixture refusal")
    }
}

private struct OrchestratorFixture {
    let request: InteractionRequest
    let snapshot: ContextSnapshot
    let runtime: RuntimeSpy
    let orchestrator: AgentOrchestrator

    static func success(payload: String) -> Self {
        make(payload: payload, inputGate: AllowingInputGate())
    }

    static func inputRefused() -> Self {
        make(payload: #"{"value":"unused"}"#, inputGate: RefusingInputGate())
    }

    private static func make(payload: String, inputGate: any InputGating) -> Self {
        let invocationID = UUID()
        let sessionID = UUID()
        let ref = ResourceRef(kind: "task", id: "t1")
        let request = InteractionRequest(
            invocationID: invocationID,
            sessionID: sessionID,
            recipeHint: "fixture.recipe",
            inputText: "go",
            selectedResources: [ref]
        )
        let recipe = RecipeDefinition(
            id: "fixture.recipe",
            family: "fixture",
            version: "1",
            title: "Fixture",
            fetchPolicy: FetchPolicy(
                allowedKinds: ["task"],
                maxItems: 1,
                maxCharactersPerItem: 100,
                maxTotalCharacters: 100
            ),
            outputSchemaID: "fixture.v1",
            runtimeRequirements: .messagesOnly,
            approvalPolicy: .none,
            timeoutSeconds: 30,
            allowsFormatRepair: false
        )
        let snapshot = ContextSnapshot(
            id: UUID(),
            createdAt: .distantPast,
            sections: [ContextSection(ref: ref, text: "fenced", trusted: false)],
            warnings: [],
            revision: "r1"
        )
        let seenSet = SeenSet(snapshotID: snapshot.id, resources: [ref])
        let runtime = RuntimeSpy(payload: Data(payload.utf8))
        let fixtureExtension = FixtureExtension(recipe: recipe, invocationID: invocationID, snapshotID: snapshot.id)

        return Self(
            request: request,
            snapshot: snapshot,
            runtime: runtime,
            orchestrator: AgentOrchestrator(
                registry: try! ExtensionRegistry(extensions: [fixtureExtension]),
                context: FrozenContextFixture(snapshot: snapshot, seenSet: seenSet),
                runtimeRouter: RuntimeRouter(messages: runtime),
                inputGate: inputGate,
                presentationGate: AllowingPresentationGate()
            )
        )
    }
}

private extension RuntimeCredentials {
    static let fixture = RuntimeCredentials(baseURL: "https://example.com", apiKey: "key", model: "model")
}
