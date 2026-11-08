import Foundation
import Observation

/// The display refreshes independently of UI statistics and durable checkpoints.
@Observable @MainActor final class ScoreVisualClock {
    private(set) var isAnimating = false
    private(set) var revision = 0
    @ObservationIgnored private var projection: ScorePlaybackProjection
    @ObservationIgnored private var displayed: (tick: Int,loop: Int)?
    init(run: ScoreRun,uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) { projection = .init(run: run,uptime: uptime) }
    func synchronize(_ run: ScoreRun,at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let previous = projection.run
        let moving = run.state == .playing || run.state == .countingIn
        if !moving || !isAnimating || previous.range != run.range || previous.speed != run.speed
            || previous.id != run.id || run.playbackLoops < previous.playbackLoops
            || (run.playbackLoops == previous.playbackLoops && run.positionSeconds < previous.positionSeconds) {
            displayed = nil
        }
        projection = .init(run: run,uptime: uptime)
        isAnimating = moving
        if !isAnimating { revision &+= 1 }
    }
    var tick: Int { tick(at: ProcessInfo.processInfo.systemUptime) }
    func tick(at uptime: TimeInterval) -> Int {
        let next = projection.position(at: uptime)
        guard isAnimating else { return next.tick }
        if let displayed,next.loop < displayed.loop || (next.loop == displayed.loop && next.tick < displayed.tick) {
            return displayed.tick
        }
        displayed = next
        return next.tick
    }
}
