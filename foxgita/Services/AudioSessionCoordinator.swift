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

    /// Refcount per need so overlapping clients (e.g. metronome + diagnosis clip)
    /// do not deactivate the session when only one of them releases.
    private var needCounts: [Need: Int] = [:]
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
        needCounts[need, default: 0] += 1
        try applyCategory()
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
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func applyCategory() throws {
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
