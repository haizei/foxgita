import AVFoundation
import Speech

@Observable
@MainActor
final class NoteDictationService {
    private(set) var isRecording = false
    private(set) var isPreparing = false
    private(set) var isFinishing = false
    private(set) var transcript = ""
    private(set) var lastError: String?
    private(set) var inputLevels = Array(repeating: Float.zero, count: 32)
    private(set) var elapsedSeconds: TimeInterval = 0

    var elapsedDisplay: String {
        let seconds = Int(elapsedSeconds)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var captureStartedAt: Date?
    private var lastLevelUpdate = Date.distantPast

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finalContinuation: CheckedContinuation<String?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var ownsAudioSession = false
    private var tapInstalled = false
    private var recognitionFinished = false
    private var generation = UUID()

    func start() async -> Bool {
        guard !isRecording, !isPreparing, !isFinishing else { return false }
        isPreparing = true
        lastError = nil
        transcript = ""
        inputLevels = Array(repeating: 0, count: 32)
        elapsedSeconds = 0
        lastLevelUpdate = .distantPast
        recognitionFinished = false
        let currentGeneration = UUID()
        generation = currentGeneration
        defer { isPreparing = false }

        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard generation == currentGeneration else { return false }
        guard speechAllowed else {
            lastError = "需要语音识别权限才能转成文字"
            return false
        }
        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
        guard generation == currentGeneration else { return false }
        guard microphoneAllowed else {
            lastError = "需要麦克风权限才能语音输入"
            return false
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            lastError = "此设备暂不支持离线语音转文字，请使用键盘输入"
            return false
        }

        do {
            try AudioSessionCoordinator.shared.acquire(.record)
            ownsAudioSession = true
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                // Only a scalar crosses to the main actor; audio buffers stay on the capture thread.
                let level = Self.captureLevel(buffer)
                Task { @MainActor [weak self] in
                    guard let self, self.generation == currentGeneration, self.isRecording else { return }
                    let now = Date()
                    guard now.timeIntervalSince(self.lastLevelUpdate) >= 0.05 else { return }
                    self.lastLevelUpdate = now
                    self.inputLevels.removeFirst()
                    self.inputLevels.append(level)
                    self.elapsedSeconds = max(0, now.timeIntervalSince(self.captureStartedAt ?? now))
                }
            }
            tapInstalled = true
            self.engine = engine
            self.request = request
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.generation == currentGeneration else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.recognitionFinished = true
                            self.resolve(self.transcript)
                        }
                    }
                    if error != nil {
                        self.lastError = "语音识别失败，请重试或使用键盘输入"
                        if self.finalContinuation != nil {
                            self.resolve(nil)
                        } else {
                            self.stopCapture()
                            self.cleanup()
                        }
                    }
                }
            }
            engine.prepare()
            try engine.start()
            captureStartedAt = Date()
            isRecording = true
            return true
        } catch {
            lastError = "无法开始语音输入，请重试"
            cleanup()
            return false
        }
    }

    func finish() async -> String? {
        guard isRecording else { return nil }
        stopCapture()
        isFinishing = true
        return await withCheckedContinuation { continuation in
            finalContinuation = continuation
            request?.endAudio()
            if recognitionFinished {
                resolve(transcript)
                return
            }
            let finishingGeneration = generation
            timeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(3)) }
                catch { return }
                guard let self, self.generation == finishingGeneration else { return }
                self.resolve(self.transcript)
            }
        }
    }

    func cancel() {
        stopCapture()
        if finalContinuation != nil {
            resolve(nil)
        } else {
            cleanup()
        }
    }

    nonisolated static func normalizedLevel(rms: Float) -> Float {
        guard rms.isFinite, rms > 0 else { return 0 }
        return min(1, max(0, (20 * log10(rms) + 50) / 50))
    }

    nonisolated private static func captureLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        return normalizedLevel(rms: sqrt(sum / Float(buffer.frameLength)))
    }

    private func stopCapture() {
        guard isRecording else { return }
        if let captureStartedAt { elapsedSeconds = max(0, Date().timeIntervalSince(captureStartedAt)) }
        engine?.inputNode.removeTap(onBus: 0)
        tapInstalled = false
        engine?.stop()
        isRecording = false
    }

    private func resolve(_ result: String?) {
        guard let continuation = finalContinuation else {
            // A recognition result may arrive before the finger is released.
            return
        }
        finalContinuation = nil
        let text = result?.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanup()
        continuation.resume(returning: text?.isEmpty == false ? text : nil)
    }

    private func cleanup() {
        generation = UUID()
        isFinishing = false
        timeoutTask?.cancel()
        timeoutTask = nil
        task?.cancel()
        task = nil
        request = nil
        if tapInstalled {
            engine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine?.isRunning == true { engine?.stop() }
        engine = nil
        captureStartedAt = nil
        isRecording = false
        if ownsAudioSession {
            AudioSessionCoordinator.shared.release(.record)
            ownsAudioSession = false
        }
    }
}
