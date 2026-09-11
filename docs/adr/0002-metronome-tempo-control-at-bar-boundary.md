# Use one tempo controller and the audio timeline for bar-boundary changes

TAP adoption and tempo-ramp changes must land on an audible bar downbeat, while the current engine schedules audio about 150 ms ahead and exposes a scheduling-ahead UI beat. We will route manual, TAP, ramp, pause, and interruption intents through one `MetronomeTempoController`; `MetronomeEngine` remains the sole audio clock and publishes token-guarded audible beat/bar events. Manual adjustment may use the next scheduled click for responsive feedback, but TAP and ramp commands commit only at an engine-owned bar boundary. This prevents sheets or UI timers from becoming competing tempo authorities and lets an active ramp survive Speed Sheet dismissal.

**Considered:** keeping all state in `MetronomeEngine` was rejected because TAP and training lifecycle are not audio-rendering responsibilities; keeping state in each sheet was rejected because dismissing a sheet would destroy active work and allow competing BPM writes.

**Consequences:** SwiftUI must stop calling `MetronomeEngine.setBpm` directly; Beat Bars, haptics, and ramp progress subscribe to the same audible timeline. This ADR supersedes only ADR-0001's TAP deferral; ADR-0001's separate Speed Sheet and Meter Sheet boundary remains accepted.
