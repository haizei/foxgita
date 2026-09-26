import Foundation
import Testing
@testable import foxgita

struct PhotoPlanGenerationPipelineTests {
    @Test func regenerationReusesSessionPreparedImagesButCreatesANewInvocation() async throws {
        let preparer = PreparedImageSpy()
        let runner = ImagePlanRunnerSpy()
        let session = PhotoPlanImageSession()
        let pipeline = PhotoPlanGenerationPipeline(
            session: session,
            preparer: preparer,
            runner: runner
        )
        let request = PhotoPlanGenerationRequest(
            sourceImages: [Data([0x01, 0x02])],
            fallbackCategory: .chord,
            credentials: RuntimeCredentials(baseURL: "https://example.test", apiKey: "key", model: "vision-fast"),
            invocationID: UUID()
        )

        _ = try await pipeline.generate(request)
        _ = try await pipeline.generate(
            PhotoPlanGenerationRequest(
                sourceImages: request.sourceImages,
                fallbackCategory: request.fallbackCategory,
                credentials: request.credentials,
                invocationID: UUID()
            )
        )

        #expect(await preparer.callCount == 1)
        #expect(await runner.invocationIDs.count == 2)
        #expect(await runner.receivedAssetByteCounts == [[3], [3]])
    }

    @Test func cancellationDuringPreparationNeverCallsTheModel() async throws {
        let runner = ImagePlanRunnerSpy()
        let pipeline = PhotoPlanGenerationPipeline(
            session: PhotoPlanImageSession(),
            preparer: SlowPreparedImageSpy(),
            runner: runner
        )
        let request = PhotoPlanGenerationRequest(
            sourceImages: [Data([0x01])],
            fallbackCategory: .chord,
            credentials: RuntimeCredentials(baseURL: "https://example.test", apiKey: "key", model: "vision-fast"),
            invocationID: UUID()
        )
        let task = Task { try await pipeline.generate(request) }
        await Task.yield()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await runner.invocationIDs.isEmpty)
    }
}

private actor PreparedImageSpy: PhotoPlanImagePreparing {
    private(set) var callCount = 0

    func prepare(_ sourceImages: [Data]) async throws -> [PreparedImageAsset] {
        callCount += 1
        return [
            PreparedImageAsset(
                id: "prepared-1",
                jpegData: Data([0x0A, 0x0B, 0x0C]),
                pixelWidth: 1024,
                pixelHeight: 768,
                quality: .standard,
                sourceKind: .camera,
                fingerprint: "fixture"
            )
        ]
    }
}

private actor ImagePlanRunnerSpy: ImagePlanRunning {
    private(set) var invocationIDs: [UUID] = []
    private(set) var receivedAssetByteCounts: [[Int]] = []

    func runImagePlan(
        imageJPEGData: [Data],
        fallbackCategory: PracticeCategory,
        credentials: RuntimeCredentials,
        invocationID: UUID
    ) async throws -> AIPracticeDraft {
        invocationIDs.append(invocationID)
        receivedAssetByteCounts.append(imageJPEGData.map(\.count))
        return AIPracticeDraft(
            title: "和弦练习",
            category: fallbackCategory,
            targetMin: 10,
            steps: ["练习 C-G"],
            chords: ["C", "G"]
        )
    }
}

private struct SlowPreparedImageSpy: PhotoPlanImagePreparing {
    func prepare(_ sourceImages: [Data]) async throws -> [PreparedImageAsset] {
        try await Task.sleep(for: .seconds(5))
        return []
    }
}
