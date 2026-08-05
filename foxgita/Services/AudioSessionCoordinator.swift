//
//  AudioSessionCoordinator.swift
//  foxgita
//

import AVFoundation
import Foundation

/// Single owner of `AVAudioSession`. The metronome and the recorder used to set
/// the category independently, so starting the metronome mid-take downgraded
/// the session from `.playAndRecord` to `.playback` and killed the recording.
/// Everything now declares a need and the coordinator picks the widest one.
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    enum Need: Hashable {
        case playback
        case record
    }

    private var needs: Set<Need> = []
    private var observer: NSObjectProtocol?

    /// Invoked when the system interrupts audio (call, alarm) so engines can
    /// stop instead of sitting in a fake running state.
    var onInterruption: (() -> Void)?

    private init() {
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

    func acquire(_ need: Need) throws {
        needs.insert(need)
        try applyCategory()
    }

    func release(_ need: Need) {
        needs.remove(need)
        guard needs.isEmpty else {
            try? applyCategory()
            return
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func applyCategory() throws {
        let session = AVAudioSession.sharedInstance()
        if needs.contains(.record) {
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
        needs.removeAll()
        onInterruption?()
    }
}
