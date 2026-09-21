# Enforce countdown cutoff on the audio timeline

Countdown completion must prevent any metronome click after the configured deadline, including while the app is locked or in the background. Enforce the cutoff on the audio sample timeline and use wall-clock state for the displayed remaining time; Swift timers and local notifications are coordination and reminder mechanisms, not the authority that stops audio.

## Consequences

- The metronome scheduler must not enqueue a click at or beyond the active countdown stop frame.
- Pausing, resetting, leaving the practice, replacing the plan, or handling an audio interruption invalidates the previous cutoff so a stale completion cannot fire.
- A local notification remains necessary for an enabled background reminder, but notification authorization never determines whether the countdown itself can run or stop.
