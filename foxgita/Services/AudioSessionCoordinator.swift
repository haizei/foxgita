import AVFoundation
import Foundation

@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    enum Need: Hashable {
        case playback
        case record
    }

    private var needCounts: [Need: Int] = [:]
    private var observer: NSObjectProtocol?
    private let applyOverride: (@MainActor () throws -> Void)?

    var onInterruption: (() -> Void)?

    var prefersPlayAndRecord: Bool { needCounts[.record, default: 0] > 0 }

    init(apply: (@MainActor () throws -> Void)? = nil) {
        applyOverride = apply
        guard apply == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleInterruption(note) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func count(for need: Need) -> Int { needCounts[need, default: 0] }

    func acquire(_ need: Need) throws {
        needCounts[need, default: 0] += 1
        do {
            try applyCategory()
        } catch {
            rollback(need)
            throw error
        }
    }

    func release(_ need: Need) {
        guard let count = needCounts[need], count > 0 else { return }
        if count == 1 {
            needCounts.removeValue(forKey: need)
        } else {
            needCounts[need] = count - 1
        }
        guard needCounts.isEmpty else {
            try? applyCategory()
            return
        }
        guard applyOverride == nil else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func rollback(_ need: Need) {
        guard let count = needCounts[need], count > 0 else { return }
        if count == 1 {
            needCounts.removeValue(forKey: need)
        } else {
            needCounts[need] = count - 1
        }
    }

    private func applyCategory() throws {
        if let applyOverride {
            try applyOverride()
            return
        }
        let session = AVAudioSession.sharedInstance()
        if needCounts[.record, default: 0] > 0 {
            try session.setCategory(
                .playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers]
            )
        } else {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try session.setActive(true)
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        guard type == .began else { return }
        needCounts.removeAll()
        onInterruption?()
    }
}
