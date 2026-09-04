import Foundation
import UIKit

enum ImageStepGeneratorError: Error, Equatable {
    case notConfigured
    case noImages
    case tooManyImages
    case failed(VisionPracticeError)

    var userMessage: String {
        switch self {
        case .notConfigured:
            return String(localized: "先去设置里填写 AI 接口")
        case .noImages:
            return String(localized: "请选择图片")
        case .tooManyImages:
            return String(localized: "一次最多 3 张图片")
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

enum PracticeImageCodec {
    static func jpegData(
        from imageData: Data,
        maxEdge: CGFloat = 1280,
        quality: CGFloat = 0.7
    ) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        // Prefer pixel size when available so @2x/@3x sources shrink correctly.
        let pixelWidth = image.cgImage.map { CGFloat($0.width) } ?? (size.width * image.scale)
        let pixelHeight = image.cgImage.map { CGFloat($0.height) } ?? (size.height * image.scale)
        let longest = max(pixelWidth, pixelHeight)
        let factor = longest > maxEdge ? maxEdge / longest : 1
        let target = CGSize(
            width: max(1, floor(pixelWidth * factor)),
            height: max(1, floor(pixelHeight * factor))
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

@MainActor
final class ImageStepGenerator {
    private let client: any VisionGenerating
    private let credentials: LLMCredentialsStore
    private let log: any AIInvocationRecording

    init(
        client: any VisionGenerating,
        credentials: LLMCredentialsStore = LLMCredentialsStore(),
        log: any AIInvocationRecording = EmptyAIInvocationLog()
    ) {
        self.client = client
        self.credentials = credentials
        self.log = log
    }

    func generate(
        imageData: [Data],
        baseURL: String,
        model: String,
        fallbackCategory: PracticeCategory,
        invocationId: String
    ) async throws -> AIPracticeDraft {
        if imageData.isEmpty {
            throw ImageStepGeneratorError.noImages
        }
        if imageData.count > 3 {
            throw ImageStepGeneratorError.tooManyImages
        }
        guard credentials.isConfigured(baseURL: baseURL, model: model) else {
            await recordNotConfigured(invocationId: invocationId, model: model)
            throw ImageStepGeneratorError.notConfigured
        }
        guard let apiKey = credentials.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            await recordNotConfigured(invocationId: invocationId, model: model)
            throw ImageStepGeneratorError.notConfigured
        }

        let jpegs = imageData.compactMap { PracticeImageCodec.jpegData(from: $0) }
        guard !jpegs.isEmpty else {
            throw ImageStepGeneratorError.noImages
        }

        do {
            return try await client.generateDraft(
                baseURL: baseURL,
                model: model,
                apiKey: apiKey,
                imageJPEGData: jpegs,
                fallbackCategory: fallbackCategory,
                invocationId: invocationId
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VisionPracticeError {
            throw ImageStepGeneratorError.failed(error)
        } catch {
            if AIInvocationStore.errorType(from: error) == .cancelled {
                throw error
            }
            throw ImageStepGeneratorError.failed(.transport)
        }
    }

    private func recordNotConfigured(invocationId: String, model: String) async {
        let skill = SkillRegistry.builtin.skill(id: SkillID.planFromImage)!
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
