//
//  AudioRecorderService.swift
//  foxgita
//

import AVFoundation
import Foundation

@Observable
final class AudioRecorderService {
    /// A finished take that has not been attached to a session yet.
    struct Clip: Identifiable, Sendable {
        let id: String
        let fileName: String
        let bytes: Int
        let durationSec: Int
        let createdAt: Date
        let label: String

        var url: URL { RecordingStore.url(for: fileName) }
    }

    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var elapsedSec = 0
    private(set) var lastError: String?
    private(set) var pending: [Clip] = []

    var elapsedDisplay: String {
        String(format: "%02d:%02d", elapsedSec / 60, elapsedSec % 60)
    }

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var currentFile: String?
    @ObservationIgnored private var ticker: Timer?

    func start(label: String = "") async {
        lastError = nil
        guard await requestMic() else {
            lastError = String(localized: "需要麦克风权限才能录音")
            return
        }
        do {
            try AudioSessionCoordinator.shared.acquire(.record)
        } catch {
            lastError = String(localized: "无法启动录音会话")
            return
        }

        let name = RecordingStore.newFileName()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let recorder = try AVAudioRecorder(url: RecordingStore.url(for: name), settings: settings)
            recorder.record()
            self.recorder = recorder
            currentFile = name
            isRecording = true
            isPaused = false
            elapsedSec = 0
            startTicker()
        } catch {
            AudioSessionCoordinator.shared.release(.record)
            lastError = String(localized: "无法开始录音")
        }
    }

    func pause() {
        guard isRecording, !isPaused, let recorder else { return }
        recorder.pause()
        isPaused = true
        stopTicker()
        elapsedSec = Int(recorder.currentTime.rounded())
    }

    func resume() {
        guard isRecording, isPaused, let recorder else { return }
        recorder.record()
        isPaused = false
        startTicker()
    }

    func stop(label: String = "") {
        guard isRecording, let recorder, let name = currentFile else { return }
        // Read the duration before stopping; afterwards currentTime resets.
        let duration = Int(recorder.currentTime.rounded())
        stopTicker()
        recorder.stop()
        self.recorder = nil
        currentFile = nil
        isRecording = false
        isPaused = false
        elapsedSec = 0
        AudioSessionCoordinator.shared.release(.record)

        let url = RecordingStore.url(for: name)
        pending.append(
            Clip(
                id: UUID().uuidString,
                fileName: name,
                bytes: RecordingStore.byteSize(of: url),
                durationSec: duration > 0 ? duration : RecordingStore.duration(of: url),
                createdAt: Date(),
                label: label
            )
        )
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let recorder = self.recorder else { return }
                self.elapsedSec = Int(recorder.currentTime.rounded())
            }
        }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// Discards takes that were never attached to a session, deleting the files
    /// so they do not linger until the next launch sweep.
    func discardPending() {
        for clip in pending {
            try? FileManager.default.removeItem(at: clip.url)
        }
        pending = []
    }

    func consume() -> [Clip] {
        let items = pending
        pending = []
        return items
    }

    /// Drops the take from `pending` but leaves the file for a persisted `RecordingRef`.
    func detach(_ id: String) {
        pending.removeAll { $0.id == id }
    }

    private func requestMic() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}

@Observable
final class AudioPlayerService {
    private(set) var playingId: String?
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var videoPlayer: AVPlayer?

    func toggle(url: URL, id: String) {
        if playingId == id {
            stop()
            return
        }
        stop()
        guard FileManager.default.fileExists(atPath: url.path) else {
            playingId = nil
            return
        }
        let ext = url.pathExtension.lowercased()
        if ext == "mov" || ext == "mp4" {
            do {
                try AudioSessionCoordinator.shared.acquire(.playback)
                let player = AVPlayer(url: url)
                player.play()
                videoPlayer = player
                playingId = id
            } catch {
                playingId = nil
            }
            return
        }
        do {
            try AudioSessionCoordinator.shared.acquire(.playback)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            playingId = id
        } catch {
            playingId = nil
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        videoPlayer?.pause()
        videoPlayer = nil
        playingId = nil
        AudioSessionCoordinator.shared.release(.playback)
    }
}
