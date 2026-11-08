import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

@MainActor struct ScoreLocalRecognitionJobTests {
    @Test func cancellationFinishesWithoutWaitingForTheScannerAndIgnoresItsLateResult() async throws {
        let queue = DispatchQueue(label: "test.local-recognition.cancel")
        let gate = DispatchSemaphore(value: 0)
        queue.async { gate.wait() }
        var results: [Result<RecognizedScoreDraft, Error>] = []
        let job = ScoreLocalRecognitionJob.start(timeout: 5, workerQueue: queue, operation: { check in
            try check()
            return Self.draft()
        }, completion: { results.append($0) })
        job.cancel()
        job.cancel()
        await waitUntil { !results.isEmpty }
        #expect(results.count == 1)
        if case .failure(let error) = results.first { #expect(error is CancellationError) }
        else { Issue.record("Cancellation must finish while the scanner queue is still blocked") }
        gate.signal()
        await drain(queue)
        #expect(results.count == 1)
    }

    @Test func timeoutFinishesWhileTheScannerIsBlocked() async {
        let queue = DispatchQueue(label: "test.local-recognition.timeout")
        let gate = DispatchSemaphore(value: 0)
        queue.async { gate.wait() }
        var results: [Result<RecognizedScoreDraft, Error>] = []
        let job = ScoreLocalRecognitionJob.start(timeout: 0.03, workerQueue: queue, operation: { _ in
            Self.draft()
        }, completion: { results.append($0) })
        await waitUntil { !results.isEmpty }
        if case .failure(let error) = results.first {
            #expect(error as? ScoreLocalRecognitionError == .timeout)
        } else { Issue.record("A blocked scanner must time out") }
        job.cancel()
        gate.signal()
        await drain(queue)
        #expect(results.count == 1)
    }

    @Test func cancellationAlsoFinishesWhenTheScannerIsAlreadyRunning() async {
        let queue = DispatchQueue(label: "test.local-recognition.running")
        let gate = DispatchSemaphore(value: 0)
        var results: [Result<RecognizedScoreDraft, Error>] = []
        var job: ScoreLocalRecognitionJob?
        await withCheckedContinuation { started in
            job = ScoreLocalRecognitionJob.start(timeout: 5, workerQueue: queue, operation: { _ in
                started.resume()
                gate.wait()
                return Self.draft()
            }, completion: { results.append($0) })
        }
        job?.cancel()
        await waitUntil { !results.isEmpty }
        if case .failure(let error) = results.first { #expect(error is CancellationError) }
        else { Issue.record("Cancellation waited for the active scanner") }
        gate.signal()
        await drain(queue)
        #expect(results.count == 1)
    }

    @Test func aFinishedResultIsDeliveredOnceAndCannotBeChangedByCancellation() async {
        var results: [Result<RecognizedScoreDraft, Error>] = []
        let queue = DispatchQueue(label: "test.local-recognition.success")
        let job = ScoreLocalRecognitionJob.start(timeout: 5, workerQueue: queue, operation: { _ in
            Self.draft()
        }, completion: { results.append($0) })
        await drain(queue)
        #expect(results.count == 1)
        if case .success(let draft) = results.first { #expect(draft.score.title == "识谱回归") }
        else { Issue.record("Scanner result was lost") }
        job.cancel()
        await drain(queue)
        #expect(results.count == 1)
    }

    @Test func scannerErrorsAreDeliveredWithoutLeavingTheJobRunning() async {
        var results: [Result<RecognizedScoreDraft, Error>] = []
        let queue = DispatchQueue(label: "test.local-recognition.failure")
        let job = ScoreLocalRecognitionJob.start(timeout: 5, workerQueue: queue, operation: { _ in
            throw ScoreRecognitionError.invalidFile
        }, completion: { results.append($0) })
        await drain(queue)
        #expect(results.count == 1)
        if case .failure(let error) = results.first { #expect(error is ScoreRecognitionError) }
        else { Issue.record("Scanner failure was lost") }
        job.cancel()
    }

    private nonisolated static func draft() -> RecognizedScoreDraft {
        .init(score: .init(title: "识谱回归", bars: [.init(number: 1, events: [])]), issues: [])
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func drain(_ queue: DispatchQueue) async {
        await withCheckedContinuation { continuation in
            queue.async { DispatchQueue.main.async { continuation.resume() } }
        }
    }
}
