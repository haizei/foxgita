# Tools Tab Option A Implementation Plan

> Execute in this session using the executing-plans workflow; finish with an independent Swift review.

**Goal:** Add the approved grouped tools catalog to the native Gita app.
**Architecture:** Add `.tools` between record and settings in the existing SwiftUI TabView. A feature-local catalog drives accessible reusable rows. The metronome owns an independent engine and tempo controller, reusing existing settings components without creating practice facts.
**Tech Stack:** SwiftUI, Observation, asset catalogs, XCTest, Swift Testing.
**Spec:** Approved Figma A, https://www.figma.com/design/smeuuUaTOYE1URHhIGbzyd?node-id=2740-517.

## Constraints

- Keep existing uncommitted practice, speech, localization and test changes intact.
- Reuse GitaTheme and scalable GitaFont, existing tabs and system safe areas.
- Import exact design SVGs; no temporary asset URLs at runtime.
- Seven rows in three groups. Six tools have no implementation yet: explicitly explain unavailability on tap.
- Standalone playback never creates or changes PracticeItem, elapsed practice time or training records.
- Audio failures are visible; interruption/route loss stops playback; no automatic restart. Leaving the tool stops playback and releases observation.

## Review Focus

Dynamic Type and small-screen scrolling; existing tab selection and navigation paths; audio lifetime across settings sheets/tab switches/background; truthful unavailable entries; preservation of practice configuration and records.

### Task 1: Tools catalog and navigation

Files: AppRouter.swift, MainTabView.swift, Features/Tools/ToolsView.swift, Assets.xcassets/Tool*.imageset, ToolsTabUITests.swift.

- [x] Write the UI tests and run the grouped-catalog test against the existing app; expect missing tools tab.
- [x] Implement catalog, navigation, rows and unavailable alert, using design icons and existing semantic colors.
- [x] Verify four-tab switching, all seven tool rows, tap targets and large text.

### Task 2: Standalone metronome

Files: Features/Tools/ToolMetronomeModel.swift, Features/Tools/ToolMetronomeView.swift, MetronomeSoundSheet.swift, ToolMetronomeTests.swift.

- [x] Write tests for audio failure, interruption, cleanup and independence from practice state; observe missing model failures.
- [x] Implement standalone playback with existing display/speed/meter/sound views; hide practice-only sound actions through a default-preserving option.
- [x] Run new tests plus router, engine and controller tests; run targeted UI journeys.
- [x] Inspect a simulator screenshot against A. Run independent Swift review and resolve findings.

## Execution notes

User explicitly chose A and requested implementation. Work stays in the current working tree on the existing codex branch to preserve their current code. No commit, push or release requested.

Final verification: 50 unit tests and 5 UI tests passed, zero failures/skips. Original engine stability test passed for 180.902 seconds in the first targeted run. Independent Swift review found two pending-tempo lifecycle issues; regression tests reproduced both before correction, and the final targeted run passes. No commits or publishing.
