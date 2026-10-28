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
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
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
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.resolve(self?.transcript)
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

    private func stopCapture() {
        guard isRecording else { return }
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
        isRecording = false
        if ownsAudioSession {
            AudioSessionCoordinator.shared.release(.record)
            ownsAudioSession = false
        }
    }
}
