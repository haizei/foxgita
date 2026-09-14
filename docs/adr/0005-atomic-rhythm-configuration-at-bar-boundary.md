# Commit structural rhythm configuration atomically at a bar boundary

Meter, subdivision, and accent pattern form one Rhythm Configuration. During playback, edits replace a single Pending Rhythm Change and the final complete configuration commits atomically at the next engine-owned Bar Boundary; sound mode and volume remain immediate because they do not change timeline structure. The Display Card continues to show the audible Current Rhythm Configuration while the Meter Sheet shows the Configured Rhythm Configuration with a next-bar indicator. This extends ADR-0002's audio-timeline authority beyond tempo changes and prevents mid-beat state combinations and stale subdivision indexes.

**Considered Options:** Applying each field immediately was rejected because audio, bar counting, and visual feedback could describe different rhythms. Queueing every edit was rejected because configuration editing expresses the user's latest intent, not a sequence of future arrangements.

**Consequences:** Stopping or interruption before the boundary promotes the pending configuration to the next run's configured state. Saved Metronome Configuration persists independently of whether the visit produces a valid practice record, and tests must cover shrinking subdivisions, repeated edits, interruption before commit, and atomic meter/accent transitions.
