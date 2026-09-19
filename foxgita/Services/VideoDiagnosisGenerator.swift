import Foundation

protocol VideoDiagnosisGenerating: Sendable {
    func diagnose(
        _ context: MediaReviewContext, baseURL: String, model: String, invocationId: String
    ) async throws -> VideoDiagnosisDraft
}

@MainActor
final class VideoDiagnosisGenerator: VideoDiagnosisGenerating {
    static let dependencyKind = AIRecipeDependencyKind.recipeRunner

    private let runner: any VideoDiagnosing
    private let credentials: LLMCredentialsStore
    private let images: any MediaImagePreparing
    private let log: any AIInvocationRecording

    init(
        runner: any VideoDiagnosing,
        credentials: LLMCredentialsStore = LLMCredentialsStore(),
        images: any MediaImagePreparing = FileMediaImagePreparer(),
        log: any AIInvocationRecording = EmptyAIInvocationLog()
    ) {
        self.runner = runner
        self.credentials = credentials
        self.images = images
        self.log = log
    }

    func diagnose(
        _ context: MediaReviewContext, baseURL: String, model: String, invocationId: String
    ) async throws -> VideoDiagnosisDraft {
        guard credentials.isConfigured(baseURL: baseURL, model: model) else {
            await recordNotConfigured(invocationId: invocationId, model: model)
            throw MediaReviewGeneratorError.notConfigured
        }
        guard let apiKey = credentials.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            await recordNotConfigured(invocationId: invocationId, model: model)
            throw MediaReviewGeneratorError.notConfigured
        }
        let jpegs: [Data]
        do {
            let preparer = images
            let name = context.fileName
            jpegs = try await Task.detached { try preparer.jpegImages(fileName: name) }.value
        } catch let error as MediaReviewGeneratorError {
            await recordPreparationFailure(invocationId: invocationId, model: model, error: error)
            throw error
        } catch {
            await recordPreparationFailure(invocationId: invocationId, model: model, error: .prepareFailed)
            throw MediaReviewGeneratorError.prepareFailed
        }
        guard !jpegs.isEmpty else {
            await recordPreparationFailure(invocationId: invocationId, model: model, error: .prepareFailed)
            throw MediaReviewGeneratorError.prepareFailed
        }
        do {
            return try await runner.generateDiagnosis(
                baseURL: baseURL,
                model: model,
                apiKey: apiKey,
                imageJPEGData: jpegs,
                contextText: MediaReviewGenerator.contextText(from: context),
                durationSec: context.durationSec,
                invocationId: invocationId
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VisionPracticeError {
            throw MediaReviewGeneratorError.failed(error)
        } catch let error as MediaReviewGeneratorError {
            throw error
        } catch {
            if AIInvocationStore.errorType(from: error) == .cancelled {
                throw error
            }
            throw MediaReviewGeneratorError.failed(.transport)
        }
    }

    private func recordPreparationFailure(
        invocationId: String,
        model: String,
        error: MediaReviewGeneratorError
    ) async {
        await log.record(AIInvocationRecordInput(
            id: invocationId,
            skillId: SkillID.diagnoseVideo,
            skillVersion: SkillDefinition.diagnoseVideo.version,
            model: model,
            startedAt: Date(),
            durationMs: 0,
            status: .failure,
            errorType: error == .fileMissing ? .transport : .invalidJSON,
            memoryIds: [],
            formatRetryUsed: false,
            draftOutcome: nil,
            runtime: RuntimeKind.messages.rawValue,
            executionState: .failed
        ))
    }

    private func recordNotConfigured(invocationId: String, model: String) async {
        let skill = SkillRegistry.builtin.skill(id: SkillID.diagnoseVideo)!
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
