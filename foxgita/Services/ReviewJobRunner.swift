import Foundation

enum ReviewFailureKind: Equatable, Sendable {
    case prepare, network, parse, unauthorized
}

@Observable
@MainActor
final class ReviewJobRunner {
    private(set) var activeRecordingId: String?
    private(set) var lastFailureKind: ReviewFailureKind?

    private let store: PracticeStore
    private let generator: any MediaReviewGenerating
    private let videoGenerator: any VideoDiagnosisGenerating

    private struct Job {
        var ids: [String]
        let baseURL: String
        let model: String
    }

    private var currentRemaining: [String] = []
    private var currentBaseURL = ""
    private var currentModel = ""
    private var queued: [Job] = []
    private var loopRunning = false

    init(
        store: PracticeStore,
        generator: any MediaReviewGenerating,
        videoGenerator: any VideoDiagnosisGenerating
    ) {
        self.store = store
        self.generator = generator
        self.videoGenerator = videoGenerator
    }

    func isRunning(_ id: String) -> Bool {
        if activeRecordingId == id { return true }
        if currentRemaining.contains(id) { return true }
        return queued.contains { $0.ids.contains(id) }
    }

    func enqueue(_ recordingIds: [String], baseURL: String, model: String) {
        let ids = recordingIds.filter { !isRunning($0) }
        guard !ids.isEmpty else { return }
        queued.append(Job(ids: ids, baseURL: baseURL, model: model))
        startLoopIfNeeded()
    }

    private func startLoopIfNeeded() {
        guard !loopRunning else { return }
        loopRunning = true
        Task { await self.runLoop() }
    }

    private func runLoop() async {
        defer {
            loopRunning = false
            activeRecordingId = nil
            currentRemaining = []
        }
        while true {
            if currentRemaining.isEmpty {
                guard !queued.isEmpty else { return }
                let job = queued.removeFirst()
                currentRemaining = job.ids
                currentBaseURL = job.baseURL
                currentModel = job.model
            }
            await processCurrentJob()
        }
    }

    private func processCurrentJob() async {
        while !currentRemaining.isEmpty {
            let id = currentRemaining.removeFirst()
            activeRecordingId = id
            store.markReviewsPending(recordingIds: [id])

            guard let context = store.reviewContext(recordingId: id) else {
                lastFailureKind = .prepare
                store.markReviewsFailed(recordingIds: [id])
                activeRecordingId = nil
                continue
            }

            do {
                let invocationId = UUID().uuidString
                if MediaReviewMedia.isVideo(fileName: context.fileName) {
                    let draft = try await videoGenerator.diagnose(
                        context, baseURL: currentBaseURL, model: currentModel,
                        invocationId: invocationId
                    )
                    store.applyVideoDiagnosis(recordingId: id, draft: draft)
                } else {
                    let draft = try await generator.review(
                        context, baseURL: currentBaseURL, model: currentModel,
                        invocationId: invocationId
                    )
                    store.applyReview(recordingId: id, draft: draft)
                }
            } catch let error as MediaReviewGeneratorError {
                lastFailureKind = failureKind(for: error)
                if case .failed(.unauthorized) = error {
                    store.markReviewsFailed(recordingIds: [id] + currentRemaining)
                    currentRemaining = []
                } else {
                    store.markReviewsFailed(recordingIds: [id])
                }
            } catch {
                lastFailureKind = .network
                store.markReviewsFailed(recordingIds: [id])
            }
            activeRecordingId = nil
        }
    }

    private func failureKind(for error: MediaReviewGeneratorError) -> ReviewFailureKind {
        switch error {
        case .fileMissing, .prepareFailed:
            return .prepare
        case .failed(.unauthorized):
            return .unauthorized
        case .failed(.invalidJSON):
            return .parse
        case .failed, .notConfigured:
            return .network
        }
    }
}
