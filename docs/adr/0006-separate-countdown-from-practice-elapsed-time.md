# Separate countdown from practice elapsed time

The countdown is a temporary pacing aid, while practice elapsed time is the durable record of work actually performed. Keep them as separate state: countdown display, pause, adjustment, completion, and reset must never replace or reduce the accumulated practice duration that is saved with the practice item. This avoids persisting “time remaining” as “time practiced” and lets countdown reset remain a local control rather than an irreversible practice reset.

## Consequences

- Starting, pausing, and resuming a countdown also drives metronome playback and practice elapsed time, but each retains its own value and meaning.
- Countdown completion pauses playback and elapsed-time accumulation without automatically completing or saving the practice.
- Countdown configuration is scoped to the current practice visit; background and lock-screen continuity are supported, while leaving the detail screen cancels the countdown.
