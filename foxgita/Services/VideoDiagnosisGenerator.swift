import Foundation

protocol VideoDiagnosisGenerating: Sendable {
    func diagnose(
        _ context: MediaReviewContext, baseURL: String, model: String
    ) async throws -> VideoDiagnosisDraft
}

@MainActor
final class VideoDiagnosisGenerator: VideoDiagnosisGenerating {
    private let client: any VideoDiagnosing
    private let credentials: LLMCredentialsStore
    private let images: any MediaImagePreparing

    init(
        client: any VideoDiagnosing,
        credentials: LLMCredentialsStore = LLMCredentialsStore(),
        images: any MediaImagePreparing = FileMediaImagePreparer()
    ) {
        self.client = client
        self.credentials = credentials
        self.images = images
    }

    func diagnose(
        _ context: MediaReviewContext, baseURL: String, model: String
    ) async throws -> VideoDiagnosisDraft {
        guard credentials.isConfigured(baseURL: baseURL, model: model) else {
            throw MediaReviewGeneratorError.notConfigured
        }
        guard let apiKey = credentials.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            throw MediaReviewGeneratorError.notConfigured
        }
        let jpegs: [Data]
        do {
            let preparer = images
            let name = context.fileName
            jpegs = try await Task.detached { try preparer.jpegImages(fileName: name) }.value
        } catch let error as MediaReviewGeneratorError {
            throw error
        } catch {
            throw MediaReviewGeneratorError.prepareFailed
        }
        guard !jpegs.isEmpty else { throw MediaReviewGeneratorError.prepareFailed }
        do {
            return try await client.generateDiagnosis(
                baseURL: baseURL,
                model: model,
                apiKey: apiKey,
                imageJPEGData: jpegs,
                contextText: MediaReviewGenerator.contextText(from: context),
                durationSec: context.durationSec
            )
        } catch let error as VisionPracticeError {
            throw MediaReviewGeneratorError.failed(error)
        } catch let error as MediaReviewGeneratorError {
            throw error
        } catch {
            throw MediaReviewGeneratorError.failed(.transport)
        }
    }
}
