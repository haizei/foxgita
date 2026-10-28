import Foundation

/// Writes local transactions on the main actor; only the debounce is asynchronous.
@MainActor @Observable
final class PracticeNoteAutosaver {
    enum State: Equatable {
        case saved, saving, failed(String)
    }
    private(set) var state: State = .saved
    private(set) var savedText: String
    @ObservationIgnored private var draft: String
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let save: (String) throws -> Void

    init(initialText: String, delay: Duration = .milliseconds(600), save: @escaping (String) throws -> Void) {
        savedText = initialText
        draft = initialText
        self.delay = delay
        self.save = save
    }

    func schedule(_ text: String) {
        draft = text
        revision += 1
        pending?.cancel()
        guard text != savedText else { state = .saved; return }
        state = .saving
        let version = revision
        pending = Task { [weak self, delay] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled, self.revision == version else { return }
            // flush records a visible error and retains the draft for an explicit retry.
            do { try self.flush() }
            catch { self.state = .failed(error.localizedDescription) }
        }
    }

    func flush() throws {
        pending?.cancel()
        pending = nil
        revision += 1
        guard draft != savedText else { state = .saved; return }
        do {
            try save(draft)
            savedText = draft
            state = .saved
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    deinit { pending?.cancel() }
}
