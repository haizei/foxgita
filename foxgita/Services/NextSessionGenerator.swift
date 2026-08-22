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

    init(
        client: any NextSessionGenerating,
        credentials: LLMCredentialsStore = LLMCredentialsStore()
    ) {
        self.client = client
        self.credentials = credentials
    }

    func generate(
        budgetMinutes: Int,
        baseURL: String,
        model: String,
        fallbackCategory: PracticeCategory
    ) async throws -> AIPracticeDraft {
        guard credentials.isConfigured(baseURL: baseURL, model: model) else {
            throw NextSessionGeneratorError.notConfigured
        }
        guard let apiKey = credentials.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            throw NextSessionGeneratorError.notConfigured
        }
        do {
            return try await client.generateDraft(
                baseURL: baseURL,
                model: model,
                apiKey: apiKey,
                budgetMinutes: budgetMinutes,
                fallbackCategory: fallbackCategory
            )
        } catch let error as VisionPracticeError {
            throw NextSessionGeneratorError.failed(error)
        } catch {
            throw NextSessionGeneratorError.failed(.transport)
        }
    }
}
