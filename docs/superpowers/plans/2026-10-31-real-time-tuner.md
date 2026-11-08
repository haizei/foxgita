# Real-time Guitar Tuner Implementation Plan

**Goal:** Implement the selected headstock tuner in the existing SwiftUI application and add it as the first tuning tool (8 tools total).
**Spec:** Figma `2745:255`, entry `2754:107`, file `smeuuUaTOYE1URHhIGbzyd`.

## Scope and decisions

- Real microphone input; local YIN pitch estimation; no recording files, uploads, practice-time or session writes.
- Six-string standard tuning with manual targets/automatic identification. Dropdown also offers Drop D and DADGAD using the same six targets.
- A4 430–450 Hz, default 440; ±6 cent in-tune band; preserve octave differences; reject silence/noise and clear stale readings.
- Reference tone uses selected calibrated target; suspend microphone during playback to avoid feedback.
- Leave/background/interruption/route loss stops input and output. Interrupted/background capture requires explicit resume. Ignore late permission and stale audio callbacks.
- Preserve all pre-existing worktree changes. Use existing AudioSessionCoordinator with balanced acquisition/release, GitaTheme and scalable fonts. Download exact Figma assets.
- Synthetic UI input is DEBUG + UITesting only and runs through the real estimator; production always uses microphone input.

## Tasks

- [x] Write estimator/model tests; observe missing-feature failures before implementation.
- [x] Implement pure pitch detector, target/cent math and faded reference WAV generation.
- [x] Implement bounded background audio analysis, microphone permission/input and reference playback service; lifecycle-owning model.
- [x] Implement headstock SwiftUI layout, settings, manual/automatic string selection and honest permission/no-signal/error states; update tools navigation/count.
- [x] Run algorithm/model tests, full unit suite and tuner/tools UI regressions; compare simulator screenshots to design.
- [x] Independent Swift code review; resolve findings with regression coverage; document validation and remaining physical-device verification.
