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
                    let capabilities = ProviderCapabilityResolver.resolve(
                        baseURL: credentials.baseURL,
                        model: credentials.model
                    )
                    let request = MessagesTransportRequest(
                            baseURL: credentials.baseURL,
                            apiKey: credentials.apiKey,
                            model: credentials.model,
                            systemPrompt: prompt.staticSystem,
                            userText: userText(for: prompt),
                            imageJPEGData: plan.mediaResources.map(\.data),
                            orderedTools: prompt.orderedTools,
                            includeResponseFormat: capabilities.supportsResponseFormat,
                            // Capability discovery must never create a hidden
                            // second paid model request.
                            allowsFormatRetry: false,
                            timeout: plan.recipe.timeoutSeconds
                    )
                    let result: AITransportResult
                    if capabilities.supportsSSE {
                        result = try await transport.stream(request) { delta in
                            continuation.yield(.modelDelta(delta))
                        }
                    } else {
                        result = try await transport.complete(request)
                    }
                    try Task.checkCancellation()

                    guard !result.content.isEmpty else {
                        continuation.yield(.failed(.emptyContent))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.artifactProduced(Data(result.content.utf8)))
                    if result.formatRetryUsed {
                        continuation.yield(.formatRepairUsed)
                    }
                    continuation.yield(.completed(result.usage))
                } catch let error as AIRuntimeError where error == .cancelled {
                    continuation.yield(.cancelled)
                } catch let error as AIRuntimeError {
                    continuation.yield(.failed(error))
                } catch is CancellationError {
                    continuation.yield(.cancelled)
                } catch {
                    continuation.yield(.failed(.transport))
                }

                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func userText(for prompt: PromptAssembly) -> String {
        ([prompt.dynamicContext] + prompt.history + [prompt.currentInput])
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

}
