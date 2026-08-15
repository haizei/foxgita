import Foundation

@Observable
@MainActor
final class ReviewJobRunner {
    private(set) var activeRecordingId: String?

    private let store: PracticeStore
    private let generator: any MediaReviewGenerating

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

    init(store: PracticeStore, generator: any MediaReviewGenerating) {
        self.store = store
        self.generator = generator
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
                store.markReviewsFailed(recordingIds: [id])
                activeRecordingId = nil
                continue
            }

            do {
                let draft = try await generator.review(
                    context, baseURL: currentBaseURL, model: currentModel
                )
                store.applyReview(recordingId: id, draft: draft)
            } catch let error as MediaReviewGeneratorError {
                if case .failed(.unauthorized) = error {
                    store.markReviewsFailed(recordingIds: [id] + currentRemaining)
                    currentRemaining = []
                } else {
                    store.markReviewsFailed(recordingIds: [id])
                }
            } catch {
                store.markReviewsFailed(recordingIds: [id])
            }
            activeRecordingId = nil
        }
    }
}
