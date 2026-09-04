import Foundation

enum NextSessionGeneratorError: Error, Equatable {
    case notConfigured
    case failed(VisionPracticeError)

    var userMessage: String {
        switch self {
        case .notConfigured:
            return String(localized: "先去设置里填写 AI 接口")
        case .failed(let vision):
            switch vision {
            case .unauthorized:
                return String(localized: "API Key 无效或无权限")
            case .invalidJSON, .emptyContent:
                return String(localized: "模型返回格式不对，可换模型或重试")
            case .timeout:
                return String(localized: "请求超时，请重试")
            case .transport:
                return String(localized: "网络异常，请重试")
            case .invalidURL, .httpStatus, .unregisteredSkill:
                return String(localized: "生成失败，请稍后重试")
            }
        }
    }
}

@MainActor
final class NextSessionGenerator {
    private let client: any NextSessionGenerating
    private let credentials: LLMCredentialsStore
    private let log: any AIInvocationRecording

    init(
        client: any NextSessionGenerating,
        credentials: LLMCredentialsStore = LLMCredentialsStore(),
        log: any AIInvocationRecording = EmptyAIInvocationLog()
    ) {
        self.client = client
        self.credentials = credentials
        self.log = log
    }

    func generate(
        budgetMinutes: Int,
        baseURL: String,
        model: String,
        fallbackCategory: PracticeCategory,
        invocationId: String
    ) async throws -> AIPracticeDraft {
        guard credentials.isConfigured(baseURL: baseURL, model: model) else {
            await recordNotConfigured(invocationId: invocationId, model: model)
            throw NextSessionGeneratorError.notConfigured
        }
        guard let apiKey = credentials.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            await recordNotConfigured(invocationId: invocationId, model: model)
            throw NextSessionGeneratorError.notConfigured
        }
        do {
            return try await client.generateDraft(
                baseURL: baseURL,
                model: model,
                apiKey: apiKey,
                budgetMinutes: budgetMinutes,
                fallbackCategory: fallbackCategory,
                invocationId: invocationId
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VisionPracticeError {
            throw NextSessionGeneratorError.failed(error)
        } catch {
            if AIInvocationStore.errorType(from: error) == .cancelled {
                throw error
            }
            throw NextSessionGeneratorError.failed(.transport)
        }
    }

    private func recordNotConfigured(invocationId: String, model: String) async {
        let skill = SkillRegistry.builtin.skill(id: SkillID.nextSession)!
        await log.record(AIInvocationRecordInput(
            id: invocationId,
            skillId: skill.id,
            skillVersion: skill.version,
            model: model,
            startedAt: Date(),
            durationMs: 0,
            status: .failure,
            errorType: .notConfigured,
            memoryIds: [],
            formatRetryUsed: false,
            draftOutcome: nil
        ))
    }
}
