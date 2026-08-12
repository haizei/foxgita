import Foundation
import UIKit

enum ImageStepGeneratorError: Error, Equatable {
    case notConfigured
    case noImages
    case tooManyImages
    case failed(VisionPracticeError)
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

    init(
        client: any VisionGenerating,
        credentials: LLMCredentialsStore = LLMCredentialsStore()
    ) {
        self.client = client
        self.credentials = credentials
    }

    func generate(
        imageData: [Data],
        baseURL: String,
        model: String,
        fallbackCategory: PracticeCategory
    ) async throws -> AIPracticeDraft {
        if imageData.isEmpty {
            throw ImageStepGeneratorError.noImages
        }
        if imageData.count > 3 {
            throw ImageStepGeneratorError.tooManyImages
        }
        guard credentials.isConfigured(baseURL: baseURL, model: model) else {
            throw ImageStepGeneratorError.notConfigured
        }
        guard let apiKey = credentials.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
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
                fallbackCategory: fallbackCategory
            )
        } catch let error as VisionPracticeError {
            throw ImageStepGeneratorError.failed(error)
        } catch {
            throw ImageStepGeneratorError.failed(.transport)
        }
    }
}
