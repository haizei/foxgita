import Foundation
import Testing
import UIKit
@testable import foxgita

struct ImageStepGeneratorTests {
    @Test func codecShrinksLargeImage() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000))
        let ui = renderer.image { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        }
        let raw = ui.jpegData(compressionQuality: 1)!
        let out = PracticeImageCodec.jpegData(from: raw)!
        let decoded = UIImage(data: out)!
        #expect(max(decoded.size.width, decoded.size.height) <= 1280 + 1)
    }

    @Test func generatorRejectsEmptyAndTooMany() async {
        struct StubClient: VisionGenerating {
            func generateDraft(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], fallbackCategory: PracticeCategory
            ) async throws -> AIPracticeDraft {
                Issue.record("should not be called")
                throw VisionPracticeError.transport
            }
        }
        let gen = ImageStepGenerator(client: StubClient(), credentials: LLMCredentialsStore(service: "t.\(UUID().uuidString)"))
        await #expect(throws: ImageStepGeneratorError.noImages) {
            try await gen.generate(imageData: [], baseURL: "https://x", model: "m", fallbackCategory: .left)
        }
        await #expect(throws: ImageStepGeneratorError.tooManyImages) {
            try await gen.generate(
                imageData: [Data([1]), Data([2]), Data([3]), Data([4])],
                baseURL: "https://x", model: "m", fallbackCategory: .left
            )
        }
    }

    @Test func generatorRejectsNotConfigured() async {
        struct StubClient: VisionGenerating {
            func generateDraft(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], fallbackCategory: PracticeCategory
            ) async throws -> AIPracticeDraft {
                Issue.record("should not be called")
                throw VisionPracticeError.transport
            }
        }
        let credentials = LLMCredentialsStore(service: "t.\(UUID().uuidString)")
        let gen = ImageStepGenerator(client: StubClient(), credentials: credentials)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let ui = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let jpeg = ui.jpegData(compressionQuality: 0.8)!
        await #expect(throws: ImageStepGeneratorError.notConfigured) {
            try await gen.generate(
                imageData: [jpeg],
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                fallbackCategory: .left
            )
        }
    }
}
