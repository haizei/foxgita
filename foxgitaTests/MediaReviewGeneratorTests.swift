import Foundation
import Testing
@testable import foxgita

@MainActor
struct MediaReviewGeneratorTests {
    private func context(file: String = "a.m4a") -> MediaReviewContext {
        MediaReviewContext(
            recordingId: "r1", fileName: file, durationSec: 12,
            taskTitle: "和弦转换", steps: ["慢速"], bpm: 80,
            timeSig: "4/4", note: "稳一点"
        )
    }

    @Test func notConfigured() async {
        struct StubClient: MediaReviewing {
            func generateReview(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String, invocationId: String
            ) async throws -> MediaReviewDraft {
                Issue.record("should not be called")
                throw VisionPracticeError.transport
            }
        }
        struct StubImages: MediaImagePreparing {
            func jpegImages(fileName: String) throws -> [Data] { [Data([1])] }
        }
        let credentials = LLMCredentialsStore(service: "t.\(UUID().uuidString)")
        let gen = MediaReviewGenerator(
            client: StubClient(), credentials: credentials, images: StubImages()
        )
        await #expect(throws: MediaReviewGeneratorError.notConfigured) {
            try await gen.review(context(), baseURL: "", model: "", invocationId: "inv-test")
        }
    }

    @Test func prepareFailedMaps() async throws {
        struct StubClient: MediaReviewing {
            func generateReview(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String, invocationId: String
            ) async throws -> MediaReviewDraft {
                throw VisionPracticeError.transport
            }
        }
        struct Boom: MediaImagePreparing {
            func jpegImages(fileName: String) throws -> [Data] {
                throw MediaReviewGeneratorError.prepareFailed
            }
        }
        let credentials = LLMCredentialsStore(service: "t.\(UUID().uuidString)")
        try credentials.saveAPIKey("sk")
        let gen = MediaReviewGenerator(
            client: StubClient(), credentials: credentials, images: Boom()
        )
        await #expect(throws: MediaReviewGeneratorError.prepareFailed) {
            try await gen.review(context(), baseURL: "https://api.openai.com/v1", model: "gpt-4o", invocationId: "inv-test")
        }
    }

    @Test func clientUnauthorizedMaps() async throws {
        struct StubClient: MediaReviewing {
            func generateReview(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String, invocationId: String
            ) async throws -> MediaReviewDraft {
                throw VisionPracticeError.unauthorized
            }
        }
        struct StubImages: MediaImagePreparing {
            func jpegImages(fileName: String) throws -> [Data] { [Data([1])] }
        }
        let credentials = LLMCredentialsStore(service: "t.\(UUID().uuidString)")
        try credentials.saveAPIKey("sk")
        let gen = MediaReviewGenerator(
            client: StubClient(), credentials: credentials, images: StubImages()
        )
        await #expect(throws: MediaReviewGeneratorError.failed(.unauthorized)) {
            try await gen.review(context(), baseURL: "https://api.openai.com/v1", model: "gpt-4o", invocationId: "inv-test")
        }
    }

    @Test func fileMissingMaps() async throws {
        struct StubClient: MediaReviewing {
            func generateReview(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String, invocationId: String
            ) async throws -> MediaReviewDraft {
                Issue.record("should not be called")
                throw VisionPracticeError.transport
            }
        }
        struct Missing: MediaImagePreparing {
            func jpegImages(fileName: String) throws -> [Data] {
                throw MediaReviewGeneratorError.fileMissing
            }
        }
        let credentials = LLMCredentialsStore(service: "t.\(UUID().uuidString)")
        try credentials.saveAPIKey("sk")
        let gen = MediaReviewGenerator(
            client: StubClient(), credentials: credentials, images: Missing()
        )
        await #expect(throws: MediaReviewGeneratorError.fileMissing) {
            try await gen.review(context(), baseURL: "https://api.openai.com/v1", model: "gpt-4o", invocationId: "inv-test")
        }
    }

    @Test func successPassesImagesAndContextText() async throws {
        final class CaptureClient: MediaReviewing, @unchecked Sendable {
            var contextText: String?
            var images: [Data] = []
            var apiKey: String?
            func generateReview(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String, invocationId: String
            ) async throws -> MediaReviewDraft {
                self.contextText = contextText
                self.images = imageJPEGData
                self.apiKey = apiKey
                return MediaReviewDraft(highlight: "h", focus: "f", nextAction: "n")
            }
        }
        struct StubImages: MediaImagePreparing {
            func jpegImages(fileName: String) throws -> [Data] { [Data([1, 2, 3])] }
        }
        let credentials = LLMCredentialsStore(service: "t.\(UUID().uuidString)")
        try credentials.saveAPIKey("sk")
        let client = CaptureClient()
        let gen = MediaReviewGenerator(
            client: client, credentials: credentials, images: StubImages()
        )
        let draft = try await gen.review(
            context(), baseURL: "https://api.openai.com/v1", model: "gpt-4o", invocationId: "inv-test"
        )
        #expect(draft == MediaReviewDraft(highlight: "h", focus: "f", nextAction: "n"))
        #expect(client.apiKey == "sk")
        #expect(client.images == [Data([1, 2, 3])])
        let text = try #require(client.contextText)
        #expect(text.contains("和弦转换"))
        #expect(text.contains("慢速"))
        #expect(text.contains("80"))
        #expect(text.contains("4/4"))
        #expect(text.contains("稳一点"))
        #expect(text.contains("12"))
        #expect(text.contains("录音"))
        #expect(!text.contains("录像"))
    }

    @Test func videoLabelOmitsEmptyNoteAndSteps() async throws {
        final class CaptureClient: MediaReviewing, @unchecked Sendable {
            var contextText: String?
            func generateReview(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String, invocationId: String
            ) async throws -> MediaReviewDraft {
                self.contextText = contextText
                return MediaReviewDraft(highlight: "h", focus: "f", nextAction: "n")
            }
        }
        struct StubImages: MediaImagePreparing {
            func jpegImages(fileName: String) throws -> [Data] { [Data([1])] }
        }
        let credentials = LLMCredentialsStore(service: "t.\(UUID().uuidString)")
        try credentials.saveAPIKey("sk")
        let client = CaptureClient()
        let gen = MediaReviewGenerator(
            client: client, credentials: credentials, images: StubImages()
        )
        let ctx = MediaReviewContext(
            recordingId: "r1", fileName: "clip.MOV", durationSec: 5,
            taskTitle: "音阶", steps: ["  ", ""], bpm: 90,
            timeSig: "3/4", note: "  "
        )
        _ = try await gen.review(ctx, baseURL: "https://api.openai.com/v1", model: "gpt-4o", invocationId: "inv-test")
        let text = try #require(client.contextText)
        #expect(text.contains("音阶"))
        #expect(text.contains("90"))
        #expect(text.contains("3/4"))
        #expect(text.contains("录像"))
        #expect(!text.contains("录音"))
        #expect(!text.contains("笔记"))
        #expect(!text.contains("步骤"))
    }

    @Test func preparerThrowsFileMissing() {
        #expect(throws: MediaReviewGeneratorError.fileMissing) {
            try FileMediaImagePreparer().jpegImages(fileName: "missing-\(UUID().uuidString).m4a")
        }
    }
}
