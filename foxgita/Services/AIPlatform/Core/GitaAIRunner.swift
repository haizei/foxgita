import Foundation
import SwiftUI

enum AIRecipeDependencyKind {
    case recipeRunner
}

private struct InvocationContextReader: ContextResourceReading {
    let resources: [ResourceRef: ContextResource]

    func fetch(ref: ResourceRef, scope: ContextFetchScope) async throws -> ContextResource {
        guard scope.authorizes(ref) else { throw ContextFetchError.notAuthorized(ref) }
        guard let resource = resources[ref] else { throw ContextFetchError.notFound(ref) }
        return resource
    }
}

struct GitaAIRunner: Sendable {
    private let orchestrator: AgentOrchestrator

    init(session: URLSession = .shared) {
        orchestrator = AgentOrchestrator(
            registry: try! ExtensionRegistry(extensions: [GitaPracticeExtension()]),
            runtimeRouter: RuntimeRouter(
                messages: MessagesRuntime(transport: AITransport(session: session))
            ),
            inputGate: StandardInputGate(),
            presentationGate: StandardPresentationGate()
        )
    }

    func run(
        request: InteractionRequest,
        resources: [ResourceRef: ContextResource],
        credentials: RuntimeCredentials
    ) async throws -> OrchestrationResult {
        try await orchestrator.run(
            request: request,
            context: ContextFetcher(reader: InvocationContextReader(resources: resources)),
            credentials: credentials
        )
    }
}

private struct GitaAIRunnerKey: EnvironmentKey {
    static let defaultValue: GitaAIRunner? = nil
}

extension EnvironmentValues {
    var gitaAIRunner: GitaAIRunner? {
        get { self[GitaAIRunnerKey.self] }
        set { self[GitaAIRunnerKey.self] = newValue }
    }
}
