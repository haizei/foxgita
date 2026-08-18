import Foundation
import Testing
@testable import foxgita

@MainActor
struct VideoDiagnosisGeneratorTests {
    private func context(file: String = "a.mov") -> MediaReviewContext {
        MediaReviewContext(
            recordingId: "r1", fileName: file, durationSec: 12,
            taskTitle: "和弦转换", steps: ["慢速"], bpm: 80,
            timeSig: "4/4", note: "稳一点"
        )
    }

    @Test func notConfigured() async {
        struct StubClient: VideoDiagnosing {
            func generateDiagnosis(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String, durationSec: Int
            ) async throws -> VideoDiagnosisDraft {
                Issue.record("should not be called")
                throw VisionPracticeError.transport
            }
        }
        struct StubImages: MediaImagePreparing {
            func jpegImages(fileName: String) throws -> [Data] { [Data([1])] }
        }
        let credentials = LLMCredentialsStore(service: "t.\(UUID().uuidString)")
        let gen = VideoDiagnosisGenerator(
            client: StubClient(), credentials: credentials, images: StubImages()
        )
        await #expect(throws: MediaReviewGeneratorError.notConfigured) {
            try await gen.diagnose(context(), baseURL: "", model: "")
        }
    }

    @Test func prepareFailedMaps() async throws {
        struct StubClient: VideoDiagnosing {
            func generateDiagnosis(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String, durationSec: Int
            ) async throws -> VideoDiagnosisDraft {
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
        let gen = VideoDiagnosisGenerator(
            client: StubClient(), credentials: credentials, images: Boom()
        )
        await #expect(throws: MediaReviewGeneratorError.prepareFailed) {
            try await gen.diagnose(context(), baseURL: "https://api.openai.com/v1", model: "gpt-4o")
        }
    }

    @Test func clientUnauthorizedMaps() async throws {
        struct StubClient: VideoDiagnosing {
            func generateDiagnosis(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String, durationSec: Int
            ) async throws -> VideoDiagnosisDraft {
                throw VisionPracticeError.unauthorized
            }
        }
        struct StubImages: MediaImagePreparing {
            func jpegImages(fileName: String) throws -> [Data] { [Data([1])] }
        }
        let credentials = LLMCredentialsStore(service: "t.\(UUID().uuidString)")
        try credentials.saveAPIKey("sk")
        let gen = VideoDiagnosisGenerator(
            client: StubClient(), credentials: credentials, images: StubImages()
        )
        await #expect(throws: MediaReviewGeneratorError.failed(.unauthorized)) {
            try await gen.diagnose(context(), baseURL: "https://api.openai.com/v1", model: "gpt-4o")
        }
    }

    @Test func fileMissingMaps() async throws {
        struct StubClient: VideoDiagnosing {
            func generateDiagnosis(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String, durationSec: Int
            ) async throws -> VideoDiagnosisDraft {
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
        let gen = VideoDiagnosisGenerator(
            client: StubClient(), credentials: credentials, images: Missing()
        )
        await #expect(throws: MediaReviewGeneratorError.fileMissing) {
            try await gen.diagnose(context(), baseURL: "https://api.openai.com/v1", model: "gpt-4o")
        }
    }

    @Test func successReturnsDraft() async throws {
        struct StubClient: VideoDiagnosing {
            func generateDiagnosis(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String, durationSec: Int
            ) async throws -> VideoDiagnosisDraft {
                VideoDiagnosisDraft(
                    highlight: "稳", focus: "F", nextAction: "慢练", findings: []
                )
            }
        }
        struct StubImages: MediaImagePreparing {
            func jpegImages(fileName: String) throws -> [Data] { [Data([1, 2, 3])] }
        }
        let credentials = LLMCredentialsStore(service: "t.\(UUID().uuidString)")
        try credentials.saveAPIKey("sk")
        let gen = VideoDiagnosisGenerator(
            client: StubClient(), credentials: credentials, images: StubImages()
        )
        let draft = try await gen.diagnose(
            context(), baseURL: "https://api.openai.com/v1", model: "gpt-4o"
        )
        #expect(draft.highlight == "稳")
        #expect(draft.focus == "F")
        #expect(draft.nextAction == "慢练")
        #expect(draft.findings.isEmpty)
    }
}
