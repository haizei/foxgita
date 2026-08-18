import Foundation
import Testing
@testable import foxgita

@MainActor
struct ReviewJobRunnerTests {
    private func harness() throws -> (
        ReviewJobRunner, PracticeStore, InMemoryPracticeRepository, RecordingSpy, VideoSpy
    ) {
        let repo = InMemoryPracticeRepository()
        let defaults = UserDefaults(suiteName: "runner.\(UUID().uuidString)")!
        defaults.set(true, forKey: SeedData.seededKey)
        let store = PracticeStore(repository: repo, defaults: defaults)
        let task = TaskItem(id: "warm", title: "指尖热身", subtitle: "", category: .left, targetMin: 5)
        try repo.add(task)
        try repo.save()
        let now = Date()
        #expect(store.finishSession(
            taskId: "warm", steps: ["a"], note: "",
            startedAt: now, endedAt: now, durationSec: 30, bpm: 80, recordings: []
        ))
        let session = try repo.sessions()[0]
        for id in ["a", "b", "c"] {
            session.recordings.append(RecordingRef(id: id, fileName: "\(id).m4a", bytes: 1, durationSec: 5))
        }
        try repo.save()
        let spy = RecordingSpy()
        let videoSpy = VideoSpy()
        let runner = ReviewJobRunner(store: store, generator: spy, videoGenerator: videoSpy)
        return (runner, store, repo, spy, videoSpy)
    }

    @Test func runsSequentiallyAndWritesReady() async throws {
        let (runner, _, repo, spy, _) = try harness()
        spy.drafts = [
            "a": .success(.init(highlight: "ha", focus: "fa", nextAction: "na")),
            "b": .success(.init(highlight: "hb", focus: "fb", nextAction: "nb")),
        ]
        runner.enqueue(["a", "b"], baseURL: "https://x", model: "m")
        try await waitUntil {
            (try? repo.recording(id: "b")?.reviewStatus) == .ready
        }
        #expect(spy.order == ["a", "b"])
        #expect(try repo.recording(id: "a")?.reviewHighlight == "ha")
        #expect(runner.isRunning("a") == false)
    }

    @Test func unauthorizedFailsRestOfBatch() async throws {
        let (runner, _, repo, spy, _) = try harness()
        spy.drafts = [
            "a": .failure(.failed(.unauthorized)),
            "b": .success(.init(highlight: "h", focus: "f", nextAction: "n")),
        ]
        runner.enqueue(["a", "b"], baseURL: "https://x", model: "m")
        try await waitUntil {
            (try? repo.recording(id: "b")?.reviewStatus) == .failed
        }
        #expect(spy.order == ["a"])
        #expect(try repo.recording(id: "a")?.reviewStatus == .failed)
        #expect(try repo.recording(id: "b")?.reviewStatus == .failed)
    }

    @Test func retryOnlyTouchesOneClip() async throws {
        let (runner, store, repo, spy, _) = try harness()
        store.markReviewsFailed(recordingIds: ["a", "b"])
        spy.drafts = [
            "a": .success(.init(highlight: "h", focus: "f", nextAction: "n")),
        ]
        runner.enqueue(["a"], baseURL: "https://x", model: "m")
        try await waitUntil {
            (try? repo.recording(id: "a")?.reviewStatus) == .ready
        }
        #expect(try repo.recording(id: "b")?.reviewStatus == .failed)
        #expect(spy.order == ["a"])
    }

    @Test func videoClipWritesFindings() async throws {
        let (runner, _, repo, _, videoSpy) = try harness()
        let session = try repo.sessions()[0]
        session.recordings.append(RecordingRef(id: "v1", fileName: "v1.mov", bytes: 1, durationSec: 20))
        try repo.save()
        videoSpy.drafts = [
            "v1": .success(
                .init(
                    highlight: "h", focus: "f", nextAction: "n",
                    findings: [
                        VideoFinding(
                            startSec: 2, endSec: 18, title: "t",
                            evidence: "e", cause: "c", action: "a"
                        )
                    ]
                )
            )
        ]
        runner.enqueue(["v1"], baseURL: "https://x", model: "m")
        try await waitUntil {
            (try? repo.recording(id: "v1")?.reviewStatus) == .ready
        }
        #expect(try repo.recording(id: "v1")?.videoFindings.count == 1)
        #expect(videoSpy.order == ["v1"])
    }
}

@MainActor
final class RecordingSpy: MediaReviewGenerating {
    var drafts: [String: Result<MediaReviewDraft, MediaReviewGeneratorError>] = [:]
    private(set) var order: [String] = []

    func review(
        _ context: MediaReviewContext, baseURL: String, model: String
    ) async throws -> MediaReviewDraft {
        order.append(context.recordingId)
        switch drafts[context.recordingId] {
        case .success(let draft): return draft
        case .failure(let error): throw error
        case nil: throw MediaReviewGeneratorError.prepareFailed
        }
    }
}

@MainActor
final class VideoSpy: VideoDiagnosisGenerating {
    var drafts: [String: Result<VideoDiagnosisDraft, MediaReviewGeneratorError>] = [:]
    private(set) var order: [String] = []

    func diagnose(
        _ context: MediaReviewContext, baseURL: String, model: String
    ) async throws -> VideoDiagnosisDraft {
        order.append(context.recordingId)
        switch drafts[context.recordingId] {
        case .success(let draft): return draft
        case .failure(let error): throw error
        case nil: throw MediaReviewGeneratorError.prepareFailed
        }
    }
}

@MainActor
func waitUntil(timeoutNanos: UInt64 = 2_000_000_000, _ pred: () -> Bool) async throws {
    let start = DispatchTime.now().uptimeNanoseconds
    while !pred() {
        if DispatchTime.now().uptimeNanoseconds - start > timeoutNanos {
            Issue.record("timeout")
            return
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
}
