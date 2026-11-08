import Foundation

nonisolated enum ScoreLocalRecognitionError: Error, Equatable, LocalizedError {
    case timeout

    var errorDescription: String? {
        "本机识谱超时，原谱已保留。请换用清晰、正面的原图后重试。"
    }
}

/// Owns a synchronous scanner's lifetime independently of Swift task-future waits.
/// The lock protects completion and deadline ownership; callbacks always run on main.
nonisolated final class ScoreLocalRecognitionJob: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@MainActor @Sendable (Result<RecognizedScoreDraft, Error>) -> Void)?
    private var deadline: DispatchWorkItem?

    private init(completion: @escaping @MainActor @Sendable (Result<RecognizedScoreDraft, Error>) -> Void) {
        self.completion = completion
    }

    static func start(
        timeout: TimeInterval,
        workerQueue: DispatchQueue = .global(qos: .userInitiated),
        operation: @escaping @Sendable (@Sendable () throws -> Void) throws -> RecognizedScoreDraft,
        completion: @escaping @MainActor @Sendable (Result<RecognizedScoreDraft, Error>) -> Void
    ) -> ScoreLocalRecognitionJob {
        precondition(timeout.isFinite && timeout > 0)
        let job = ScoreLocalRecognitionJob(completion: completion)
        let deadline = DispatchWorkItem { [weak job] in
            job?.finish(.failure(ScoreLocalRecognitionError.timeout))
        }
        job.deadline = deadline
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        workerQueue.async {
            let result = Result {
                try job.checkCancellation()
                return try operation { try job.checkCancellation() }
            }
            job.finish(result)
        }
        return job
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func checkCancellation() throws {
        lock.lock()
        let finished = completion == nil
        lock.unlock()
        if finished { throw CancellationError() }
    }

    private func finish(_ result: Result<RecognizedScoreDraft, Error>) {
        lock.lock()
        let callback = completion
        completion = nil
        let timer = deadline
        deadline = nil
        lock.unlock()
        timer?.cancel()
        if let callback {
            DispatchQueue.main.async { callback(result) }
        }
    }
}
