import Foundation
import Observation

/// Owns tool-only playback; it has no practice repository or elapsed-time state.
@MainActor @Observable
final class ToolMetronomeModel {
    let controller: MetronomeTempoController
    var playbackError: String?
    var engine: MetronomeEngine { controller.engine }

    @ObservationIgnored private let session: AudioSessionCoordinator
    @ObservationIgnored private var interruptionToken: UUID?

    init(session: AudioSessionCoordinator = .shared) {
        self.session = session
        controller = MetronomeTempoController(engine: MetronomeEngine(session: session))
    }

    func activate() {
        guard interruptionToken == nil else { return }
        interruptionToken = session.addInterruptionObserver { [weak self] event in
            self?.handle(event)
        }
    }

    func deactivate() {
        engine.stop()
        controller.resetTap()
        controller.endRamp(cancelled: true)
        settlePendingTempo()
        if let interruptionToken {
            session.removeInterruptionObserver(interruptionToken)
            self.interruptionToken = nil
        }
    }

    func togglePlayback() {
        playbackError = nil
        if engine.isPlaying {
            controller.pauseRamp()
            engine.pausePlayback()
            settlePendingTempo()
        } else {
            do {
                try engine.resumePlayback()
                controller.resumeRamp()
            } catch {
                playbackError = String(localized: "节拍器暂时无法播放，请检查音频设备后重试。")
            }
        }
    }

    func startRamp(_ settings: TempoRampSettings) {
        guard settings.validationError == nil else {
            playbackError = settings.validationError
            return
        }
        if engine.isPreviewing { engine.stopPreview() }
        controller.startRamp(settings)
        if !engine.isPlaying {
            do { try engine.start() }
            catch {
                controller.endRamp(cancelled: true)
                playbackError = String(localized: "节拍器暂时无法播放，请检查音频设备后重试。")
            }
        }
    }

    func endRamp(applying tempo: Int?) {
        controller.endRamp()
        if let tempo { controller.setTempo(tempo) }
    }

    private func settlePendingTempo() {
        // An adopted TAP value must not wait for a downbeat whose playback
        // callback was cancelled by pause, interruption or leaving this tool.
        guard let tempo = controller.pendingTempo else { return }
        controller.applyMeasuredTempo(tempo)
    }

    private func handle(_ event: AudioSessionCoordinator.InterruptionEvent) {
        switch event {
        case .ended:
            break // Playback resumes only after the user presses play.
        case .began, .outputRouteLost, .audioServicesReset:
            let wasPlaying = engine.isPlaying
            engine.stop()
            controller.resetTap()
            controller.endRamp(cancelled: true)
            settlePendingTempo()
            if event == .audioServicesReset { engine.prepareAfterAudioServicesReset() }
            if wasPlaying {
                playbackError = String(localized: "音频已中断，请检查音频设备后手动重新开始。")
            }
        }
    }
}
