import AVFoundation
import Foundation
import os

private let audioSessionLog = Logger(
    subsystem: "com.haizei.foxgita", category: "audio-session"
)

@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    enum Need: Hashable {
        case playback
        case record
    }

    enum InterruptionEvent: Equatable, Sendable {
        case began
        case ended(shouldResume: Bool)
        case outputRouteLost
        case audioServicesReset
    }

    private var needCounts: [Need: Int] = [:]
    private var observers: [NSObjectProtocol] = []
    private let applyOverride: (@MainActor () throws -> Void)?
    private var interruptionObservers: [UUID: (InterruptionEvent) -> Void] = [:]

    var prefersPlayAndRecord: Bool { needCounts[.record, default: 0] > 0 }

    init(apply: (@MainActor () throws -> Void)? = nil) {
        applyOverride = apply
        guard apply == nil else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleInterruption(note) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleRouteChange(note) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notifyInterruptionForTesting(.audioServicesReset)
            }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func count(for need: Need) -> Int { needCounts[need, default: 0] }

    @discardableResult
    func addInterruptionObserver(
        _ observer: @escaping (InterruptionEvent) -> Void
    ) -> UUID {
        let token = UUID()
        interruptionObservers[token] = observer
        return token
    }

    func removeInterruptionObserver(_ token: UUID) {
        interruptionObservers.removeValue(forKey: token)
    }

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
        switch type {
        case .began:
            notifyInterruptionForTesting(.began)
        case .ended:
            let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            notifyInterruptionForTesting(.ended(shouldResume: options.contains(.shouldResume)))
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else {
            return
        }
        notifyInterruptionForTesting(.outputRouteLost)
    }

    func notifyInterruptionForTesting(_ event: InterruptionEvent) {
        if event == .began || event == .audioServicesReset { needCounts.removeAll() }
        audioSessionLog.notice("lifecycle event=\(String(describing: event), privacy: .public)")
        let callbacks = Array(interruptionObservers.values)
        for observer in callbacks { observer(event) }
    }
}
