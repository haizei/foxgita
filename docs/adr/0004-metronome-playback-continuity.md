# Preserve metronome playback continuity across screen lock and backgrounding

An active Metronome Playback Run continues its audio, practice timer, and any active Recording Segment when the screen locks or the app enters the background; playback also prevents automatic screen sleep while the practice view is visible. Foreground Beat Feedback pauses outside the foreground to avoid useless animation and haptic work. System audio interruptions, output-route loss, and audio-service resets are different boundaries: they safely pause playback and timing, save the current recording segment, and require explicit user recovery because silent discontinuity or unexpected speaker output would make the metronome untrustworthy.

**Considered Options:** Treating lock as pause was rejected because passive listening is a primary metronome workflow. Automatically resuming after every interruption was rejected because the original phase may no longer be trustworthy and audio could resume unexpectedly.

**Consequences:** The app must declare and exercise the required background-audio capability, manage screen-awake ownership only for active foreground playback, rebuild foreground feedback from the audio timeline, and leave privacy-safe lifecycle diagnostics at every continuity boundary.
