//
//  AudioRecorderService.swift
//  foxgita
//

import AVFoundation
import Foundation

@Observable
final class AudioRecorderService {
    private(set) var isRecording = false
    private(set) var lastError: String?
    private(set) var pending: [Pending] = []
    private var recorder: AVAudioRecorder?
    private var currentFile: String?

    struct Pending: Identifiable {
        let id: String
        let fileName: String
        let bytes: Int
        let createdAt: Date
        let label: String
    }

    func start(label: String = "") async {
        lastError = nil
        let ok = await requestMic()
        guard ok else {
            lastError = "需要麦克风权限才能录音"
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch {
            lastError = "无法启动录音会话"
            return
        }
        let name = "rec-\(UUID().uuidString).m4a"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.record()
            recorder = rec
            currentFile = name
            isRecording = true
            _ = label
        } catch {
            lastError = "无法开始录音"
        }
    }

    func stop(label: String = "") {
        guard isRecording else { return }
        recorder?.stop()
        recorder = nil
        isRecording = false
        guard let name = currentFile else { return }
        currentFile = nil
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        pending.append(Pending(id: UUID().uuidString, fileName: name, bytes: bytes, createdAt: Date(), label: label))
    }

    func consume() -> [Pending] {
        let items = pending
        pending = []
        return items
    }

    private func requestMic() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }
}

@Observable
final class AudioPlayerService {
    private var player: AVAudioPlayer?
    private(set) var playingId: String?

    func toggle(url: URL, id: String) {
        if playingId == id {
            player?.stop(); playingId = nil; return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            playingId = id
        } catch {
            playingId = nil
        }
    }

    func stop() { player?.stop(); playingId = nil }
}
