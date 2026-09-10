import Foundation

struct MessagesRuntime: AgentRuntime {
    let transport: any MessagesTransporting

    func execute(
        plan: AgentExecutionPlan,
        prompt: PromptAssembly,
        credentials: RuntimeCredentials
    ) -> AsyncThrowingStream<RuntimeEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.accepted)

            let task = Task {
                continuation.yield(.started)

                do {
                    try Task.checkCancellation()
                    let result = try await transport.complete(
                        MessagesTransportRequest(
                            baseURL: credentials.baseURL,
                            apiKey: credentials.apiKey,
                            model: credentials.model,
                            systemPrompt: systemPrompt(for: prompt),
                            userText: userText(for: prompt),
                            includeResponseFormat: true,
                            allowsFormatRetry: plan.recipe.allowsFormatRepair,
                            timeout: plan.recipe.timeoutSeconds
                        )
                    )
                    try Task.checkCancellation()

                    guard !result.content.isEmpty else {
                        continuation.yield(.failed(.emptyContent))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.artifactProduced(Data(result.content.utf8)))
                    continuation.yield(.completed(result.usage))
                } catch is CancellationError {
                    continuation.yield(.cancelled)
                } catch {
                    continuation.yield(.failed(mapError(error)))
                }

                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func systemPrompt(for prompt: PromptAssembly) -> String {
        let toolSchemas = prompt.orderedTools.map(\.json)
        return ([prompt.staticSystem] + toolSchemas)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func userText(for prompt: PromptAssembly) -> String {
        ([prompt.dynamicContext] + prompt.history + [prompt.currentInput])
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func mapError(_ error: Error) -> AIRuntimeError {
        if let error = error as? VisionPracticeError {
            switch error {
            case .invalidURL:
                return .invalidURL
            case .unauthorized:
                return .unauthorized
            case .httpStatus(let status):
                return .httpStatus(status)
            case .emptyContent:
                return .emptyContent
            case .invalidJSON:
                return .invalidResponse
            case .timeout:
                return .timeout
            case .transport, .unregisteredSkill:
                return .transport
            }
        }
        if let error = error as? URLError, error.code == .timedOut {
            return .timeout
        }
        return .transport
    }
}
