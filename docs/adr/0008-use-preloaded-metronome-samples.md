# Use preloaded calibrated samples for metronome sound presets

The seven Metronome Sound Presets use bundled, preloaded, loudness-calibrated mono PCM beat/strong sample pairs instead of runtime single-sine synthesis. This adds licensed assets and an offline calibration gate, but it makes the named sounds truthful, keeps playback deterministic on the existing audio timeline, and prevents peak amplitude from being mistaken for perceived loudness; the engine must fail explicitly or fall back to the real-metronome samples rather than silently returning to the legacy synthesizer.

## Considered Options

Extending the oscillator recipes was rejected because short single-tone synthesis cannot represent chime, woodblock, drum-kit, and clap sounds or maintain comparable audibility on phone speakers. Runtime compressed-audio decoding was rejected because the assets are tiny and deterministic PCM loading avoids decoder work near playback.

## Consequences

All 14 release assets require provenance, fixed format, duration, peak, cross-preset loudness, and strong/beat-difference checks before integration. Existing sample-time scheduling, Audio Session mixing, user volume persistence, and playback-continuity behavior remain unchanged.
