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
                            systemPrompt: prompt.staticSystem,
                            userText: userText(for: prompt),
                            orderedTools: prompt.orderedTools,
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
