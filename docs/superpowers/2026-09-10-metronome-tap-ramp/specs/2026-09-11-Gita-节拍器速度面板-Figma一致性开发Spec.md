# Gita 节拍器速度面板 Figma 一致性开发 Spec

> 状态：Ready for implementation
> 日期：2026-09-11
> Figma 文件：[`吉他训记 app`](https://www.figma.com/design/smeuuUaTOYE1URHhIGbzyd/%E5%90%89%E4%BB%96%E8%AE%AD%E8%AE%B0app?node-id=58-2)
> 视觉基准：`Metronome Speed Reference / A Compact`（`1373:118`）、`Metronome Speed Reference / B Segmented`（`1373:315`）
> 关联决策：ADR-0001、ADR-0002、ADR-0003
> 适用平台：iOS 18+ / SwiftUI

## Problem Statement

用户需要在练习详情页快速完成手动调速、TAP 测速和变速训练设置，但当前 Speed Sheet 只有 BPM 加减和 Tempo Ruler：

- TAP 与变速训练尚无正式承载；
- 速度功能如果拆成多个互相叠加的 Sheet，会增加跳转成本并破坏练琴时的连续操作；
- 当前实现由 SwiftUI 直接修改 MetronomeEngine，无法安全表达 TAP 待采用、下一小节生效、训练排他和阶段进度；
- 前端如果只按文字需求实现，容易偏离 Figma 已确定的面板高度、控件位置、字号、颜色、圆角和分段状态；
- 当前 Tempo Ruler、引擎范围和此前讨论过的展示范围存在差异，需要明确“视觉范围”和“引擎范围”是两个契约。

用户需要的是一个不离开练习详情页、单手即可操作、声音与界面状态一致，并与指定 Figma 节点视觉对齐的速度控制体验。

## Solution

Speed Sheet 使用同一 presentation surface 的两种确定形态：

1. **A Compact** 是点击 Metronome Display Card 速度入口后的默认形态，提供 BPM、±、单一 TAP、Tempo Ruler 和变速训练摘要入口；
2. **B Segmented** 是进入完整速度设置后的扩展形态，使用“调速 / 测速 / 变速”分段控件，默认激活“变速”，承载 Tempo Ramp Plan 的完整参数与启动按钮。

两种形态不叠加第二个 bottom sheet。A 进入 B 时在同一个 Speed Sheet 内切换内容并改变 detent；B 选择“调速”可返回 A Compact，选择“测速”进入 TAP 专注状态，选择“变速”显示 Figma B 的参数内容。

功能状态由 MetronomeTempoController 统一管理。音频引擎仍是 Bar Boundary 的唯一事实源，TAP 和 Tempo Ramp 的既有计算、持久化和中断规则保持不变。

视觉实现以两个 Figma 节点为验收基准：SwiftUI 必须复用 GitaTheme、GitaFont、既有按钮和 Sheet 样式，将 Figma token 映射到工程 token；图片或图标必须使用 Figma 导出的原始资产或已确认完全一致的现有资产。

## User Stories

1. As a guitar learner, I want to open speed controls by tapping the speed column, so that I can adjust tempo without leaving practice detail.
2. As a guitar learner, I want the first speed surface to stay compact, so that it does not cover more practice content than necessary.
3. As a guitar learner, I want to see the current BPM prominently, so that I always know the active practice speed.
4. As a guitar learner, I want 44-point decrement and increment controls, so that I can adjust BPM reliably with one hand.
5. As a guitar learner, I want manual BPM changes to respond quickly during ordinary playback, so that small corrections do not feel delayed.
6. As a guitar learner, I want a single TAP button in A Compact, so that I do not have to choose between duplicate measurement entry points.
7. As a guitar learner, I want the TAP button to show immediate pressed feedback, so that every accepted tap feels acknowledged.
8. As a guitar learner, I want a provisional BPM after two valid taps, so that I receive useful feedback quickly.
9. As a guitar learner, I want a stable result after sufficient consistent taps, so that I know when the measurement can be trusted.
10. As a guitar learner, I want to explicitly adopt a TAP result, so that measurement never overwrites my tempo by surprise.
11. As a guitar learner, I want an adopted TAP result to apply immediately while stopped, so that setup is fast.
12. As a guitar learner, I want an adopted TAP result to apply on the next Bar Boundary while playing, so that the current bar is not broken.
13. As a guitar learner tapping slowly, I want another tap after the 0.8-second ready prompt to continue the same attempt, so that low tempos remain measurable.
14. As a guitar learner, I want a new Tap Tempo Attempt only after a two-second gap, so that accidental pauses do not discard good samples.
15. As a guitar learner, I want the compact variable-tempo card to summarize start BPM, target BPM and the change rule, so that I can review the plan before opening settings.
16. As a guitar learner, I want the variable-tempo card to have an obvious entry affordance, so that I understand it opens detailed settings.
17. As a guitar learner, I want B Segmented to remain in the same Speed Sheet, so that entering settings does not create stacked modal layers.
18. As a guitar learner, I want to switch among 调速、测速 and 变速 using a segmented control, so that all speed-related functions share one mental model.
19. As a guitar learner, I want the active segment to be visually distinct with a white inset capsule and orange label, so that the selected mode is unambiguous.
20. As a guitar learner, I want start and target BPM visible side by side, so that I can understand the direction of training at a glance.
21. As a guitar learner, I want to configure the number of bars before a speed increase, so that each stage has enough practice time.
22. As a guitar learner, I want to configure the BPM increase step, so that difficulty rises at a manageable rate.
23. As a guitar learner, I want to configure zero, one or two count-in bars, so that I can prepare before training begins.
24. As a guitar learner, I want an estimated time to target speed, so that I can decide whether the plan fits the current practice session.
25. As a guitar learner, I want invalid start and target values explained in place, so that I can fix the plan without a blocking alert.
26. As a guitar learner, I want the start button disabled when the target is not above the start, so that an invalid training run cannot begin.
27. As a guitar learner, I want starting a ramp to close the Sheet and begin the appropriate count-in or Bar Boundary transition, so that I can return my hands to the guitar.
28. As a guitar learner, I want training to survive closing the Speed Sheet, so that the plan continues while I watch the Metronome Display Card.
29. As a guitar learner, I want TAP disabled during active ramp states, so that two speed authorities cannot conflict.
30. As a guitar learner, I want meter, subdivision and Accent Pattern locked during a ramp, so that stage bar counting remains valid.
31. As a guitar learner, I want sound mode and volume to remain adjustable during a ramp, so that I can hear the click comfortably without changing its structure.
32. As a guitar learner, I want Beat Bars and current BPM to change at the same audible boundary, so that visual feedback never leads or trails the click.
33. As a guitar learner, I want pausing a ramp to pause the PracticeTimer, so that elapsed practice time follows the existing detail-page behavior.
34. As a guitar learner, I want resuming a paused ramp to start from a complete bar, so that a partial bar is not counted as training progress.
35. As a guitar learner, I want audio interruption recovery to require my confirmation, so that playback never restarts unexpectedly.
36. As a guitar learner, I want lock-screen and background playback to continue when audio remains available, so that I can practice without keeping the screen awake.
37. As a guitar learner, I want leaving practice detail to end and save an active run, so that the metronome does not continue invisibly.
38. As a guitar learner, I want the target BPM to hold after a complete target stage, so that I can keep practising at the achieved speed.
39. As a guitar learner, I want to exit Target Hold before using TAP again, so that the active training authority is explicit.
40. As a returning learner, I want my last validated plan restored for the same PracticeItem, so that repeated training takes fewer steps.
41. As a returning learner, I want unfinished runs caused by process termination recorded as interrupted but not resumed, so that history is accurate without unsafe playback.
42. As a VoiceOver user, I want every control and state to have a meaningful label and value, so that speed training is fully operable without sight.
43. As a large-text user, I want values, segments and the primary button to remain readable without clipping, so that accessibility settings do not block training.
44. As a product reviewer, I want A Compact and B Segmented to match their Figma reference nodes, so that the shipped experience reflects the approved design.

## Implementation Decisions

### Product and navigation

- Speed Sheet is the only modal surface for speed functions and remains separate from Meter Sheet and Sound Sheet.
- A Compact is the default entry state and has no segmented control. It contains one TAP button and one Tempo Ramp entry card.
- Selecting the Tempo Ramp entry changes the existing Sheet to B Segmented and expands its height; it does not present another Sheet.
- B Segmented contains three equal-purpose modes: 调速, 测速 and 变速. The Figma reference shows 变速 active and is authoritative for that state.
- Selecting 调速 returns to the A Compact content and compact height. Selecting 测速 opens the dedicated TAP state within the expanded shell. Selecting 变速 displays the plan editor.
- Draft plan values survive A/B and segment changes during the current Speed Sheet presentation. Dismissing the entire Sheet discards an unstarted draft.
- A validated plan is persisted only when the user starts training.

### Figma visual contract — A Compact

- Reference canvas width is 402 points. The Sheet is 402×382 points, begins at y=492 on the 874-point reference device, and uses a 24-point top corner radius.
- The underlying screen uses a 32% black dim overlay.
- The drag handle is 40×4 points, centered 12 points from the top, color `#C6C8CC`, radius 2.
- The header begins at x=20, y=28 with a 34-point row. “调整速度” uses 18-point bold text in `#292929`; “完成” uses 14-point regular orange text aligned to the right.
- The primary control row begins at y=84. Minus and plus controls are 44×44 points; minus starts at x=24 and plus at x=246.
- The BPM value is centered around x=160, uses 46-point medium orange text, and has a 12-point gray BPM unit below it.
- TAP is 74×44 points at x=304, uses a 22-point capsule radius, orange background and 14-point medium white text.
- Tempo Ruler uses a 322×4-point track beginning at x=40, y=176. The approved visible/direct-drag range is 40–160 with labels at 40, 80, 120 and 160. The audio engine still accepts 40–200 through steppers and TAP.
- The ruler thumb is 14×14 points and must use the exported Figma asset or an existing asset verified to be pixel-identical.
- A one-point divider spans x=20...382 at y=218.
- The Tempo Ramp entry card is 362×110 points at x=20, y=236, radius 14, background `#FFF1E8`.
- The card uses a 16-point title, 18-point orange plan summary, 12-point gray rule copy, orange chevron and 12-point “进入设置” affordance.

### Figma visual contract — B Segmented

- The Sheet is 402×498 points, begins at y=376 on the reference device, and uses the same 24-point top radius, handle and header alignment as A.
- The title is “速度设置”. The completion action remains at the top-right.
- The segmented control is 362×44 points at x=20, y=72, radius 12, background `#F6F6F6`.
- Segment widths follow the reference: 120, 121 and 117 points. The active 变速 capsule is inset 4 points, 117×36 points, radius 9, white background and subtle 0/1/4 shadow.
- Inactive labels use 14-point regular `#999999`; the active label uses 14-point medium orange.
- Start and target fields are each 174×78 points at x=20 and x=208, y=132, with 12-point gray labels, 26-point medium orange values and 12-point gray BPM units.
- The change-rule container is 362×64 points at x=20, y=224, radius 12, background `#F6F6F6`. Its value chips are 40 points high, pill-shaped, and use a one-point `#EEEEEE` border.
- The count-in row is 362×56 points at x=20, y=300, radius 12, white background and one-point `#EEEEEE` border.
- The estimate occupies a centered 22-point row at y=366 using 12-point gray text.
- The primary CTA is 362×52 points at x=20, y=410, radius 26, orange background and 14-point medium white text.
- No implementation may replace these values with approximate stock Form, Picker or List styling.

### Token and asset mapping

- `#FF7925` maps to the existing primary brand/action token; `#292929`, `#999999`, white, `#F6F6F6`, `#EEEEEE` and `#FFF1E8` map to existing semantic tokens where their rendered values match.
- Existing GitaFont styles are preferred when their family, size, weight and line height match the Figma styles; otherwise a feature-local named typography token is added instead of scattering raw font modifiers.
- The Sheet uses existing Gita radii and shadow tokens when their rendered output matches. Feature-local tokens are allowed only for missing reference values such as the 14-point plan-card radius.
- Every Figma image/SVG is downloaded into the asset catalog before implementation. Temporary MCP URLs must not ship.
- An existing project asset may replace a Figma export only after visual comparison confirms the glyph, intrinsic padding and color are identical.

### Behavior and state ownership

- MetronomeTempoController is the primary feature seam and the sole owner of visible tempo-control state.
- SwiftUI sends user intents to the controller and renders its observable state; views do not write BPM directly to MetronomeEngine.
- Tap Tempo Attempt, Tempo Ramp Plan, Tempo Ramp Run, Target Hold and Bar Boundary use the terms defined in the project glossary.
- MetronomeEngine remains the sole audio clock. TAP adoption and ramp changes commit only at audible Bar Boundary events; ordinary manual adjustments retain fast next-click behavior.
- Beat Bars, displayed BPM, haptics and ramp progress subscribe to the same audible timeline.
- TAP sampling follows the approved 250–1500 ms interval, median ±20% filtering, seven-interval rolling window, 0.8-second ready and two-second reset rules.
- Ramp training remains single-direction, bar-count based, and restricted to supported interval, step and count-in values.
- During active ramp states, TAP is disabled and structural rhythm settings are locked. Sound and volume remain editable.
- PracticeTimer starts and pauses with ramp playback. Target Hold keeps both metronome and timer running until the user exits or leaves the detail screen.

### Persistence and lifecycle

- SwiftData Schema V18 adds dedicated Tempo Ramp Plan and Metronome Training Session models instead of extending PracticeSession.
- One latest validated plan is associated with each PracticeItem; training results append per run.
- Raw TAP timestamps and intervals are never persisted.
- A process-terminated running record is closed as interrupted on the next launch. Audio and stage progress are not automatically resumed.
- Background and lock-screen operation continue while the audio session remains valid. Active audio interruptions stop playback and require explicit resume.
- Dismissing Speed Sheet does not stop training; leaving practice detail does.

### Compatibility and precedence

- This spec is the latest visual authority for A Compact and B Segmented.
- It supersedes the earlier proposal that Tempo Ruler itself display 40–200; the engine range stays 40–200 while the Figma ruler remains 40–160.
- It refines the earlier “B as navigation child” wording: B remains inside the same Speed Sheet ownership boundary, but its visible transition is a segmented expanded state rather than a pushed page with a back affordance.
- ADR-0001's separation of Speed Sheet and Meter Sheet, ADR-0002's single tempo authority and ADR-0003's persistence boundary remain unchanged.

## Testing Decisions

### Test seams

- The primary behavior seam is MetronomeTempoController. Tests send public intents and audio timeline events, then assert observable user-facing state and commands. Reducer internals, timers and private storage are not asserted directly.
- A second seam is necessary for the explicit visual requirement: the presented Speed Sheet root. Snapshot/layout tests compare A Compact and B Segmented at the 402×874 reference size and accessibility sizes. This seam is limited to geometry, semantic colors, type styles, assets and visibility—not business calculations.
- Persistence is exercised through the feature repository as observable save/load/settle behavior, not through direct model-property tests.

The two seams match the user's explicit priorities: one coherent feature behavior and pixel-aligned Figma presentation. No additional ViewModel-specific seams should be introduced.

### Good-test criteria

- Tests assert behavior a user or caller can observe: displayed state, enabled actions, emitted tempo command, audible boundary result, saved plan/result and rendered layout.
- Tests use an injectable monotonic clock and fake audio timeline; no correctness test waits on wall-clock sleep.
- Tests do not depend on private state names, AVAudioEngine implementation details or exact reducer decomposition.
- Each Figma geometry assertion names the reference node and measures the root coordinate space, avoiding fragile assertions against unrelated practice-detail content.
- Visual tests compare semantic colors after trait resolution and include default, dark appearance if supported, largest accessibility text and reduced-motion settings.

### Behavior coverage

- Opening speed shows A Compact; entering Tempo Ramp switches the same Sheet to B Segmented and the expected height.
- Segment changes preserve draft values and expose the correct mode.
- A contains exactly one TAP action; B contains the three labels shown in Figma.
- TAP preview, stability, continuation after 0.8 seconds, reset after two seconds, explicit adoption, pending Bar Boundary and cancellation are covered.
- Ramp validation, start contexts, count-in, stage progression, target stage, Target Hold, pause/resume, interruption and running manual adjustment are covered.
- Controller rejects TAP and meter changes during active ramp states while allowing sound changes.
- Closing the Sheet preserves training; leaving the detail screen settles it.
- V17 → V18 migration, latest-plan upsert, append-only results and interrupted-record settlement are covered.

### Visual coverage

- A root size, sheet y-origin/height/radius, dim opacity, header, control row, ruler, divider and plan card match node `1373:118`.
- B root size, sheet y-origin/height/radius, segmented control, fields, change rule, count-in row, estimate and CTA match node `1373:315`.
- Fonts, resolved colors, corner radii, shadow, touch targets and exported assets match the node context.
- Long localized values and large text do not clip critical values or the start CTA. Where exact fixed geometry and accessibility conflict, the default size remains pixel-aligned and accessibility sizes may grow vertically without horizontal clipping.

### Prior art

- Existing MetronomeEngine tests establish BPM clamp, playback and meter/subdivision behavior.
- Existing MetronomeTempoRuler tests establish value/fraction mapping and should remain aligned with the 40–160 visual/direct-drag range.
- Existing MetronomeDisplayCard tests establish state-driven visual assertions.
- Existing migration tests provide the V17 store fixture and Schema migration pattern.
- Existing SwiftUI/XCTest smoke tests provide the app-launch and practice-detail navigation harness.

## Out of Scope

- Implementing new visual alternatives beyond A Compact and B Segmented;
- A separate full-screen speed page or stacked Sheet presentation;
- Redesigning Metronome Display Card, Meter Sheet, Sound Sheet, PracticeTimer, practice steps or recording tools;
- Automatic BPM recognition from microphone audio;
- Automatic deceleration, ping-pong ramps, percentage ramps or time-based ramps;
- Multi-stage editable curves and cross-song plan templates;
- Cloud synchronization of plans or results;
- Resuming audio automatically after interruption or process termination;
- Changing the engine's overall 40–200 BPM capability;
- Shipping assets from temporary Figma MCP URLs.

## Further Notes

- Figma nodes `1373:118` and `1373:315` are the source of truth for default-size visual review. If those nodes change, the implementation ticket must record the new node revision before accepting pixel changes.
- A Compact intentionally combines a quick TAP action with a Tempo Ramp entry. B Segmented offers an expanded speed workspace; this is not a second Sheet and does not weaken ADR-0001.
- The visible Tempo Ruler ends at 160 to match A Compact exactly. BPM 161–200 remains reachable by step controls and adopted TAP values; when outside the ruler range, the thumb clamps to the 160 endpoint while the BPM value remains truthful.
- The Figma references show representative values (`80`, `120`, `+10 BPM`). Runtime defaults continue to follow the approved product rules; sample copy is not a hard-coded default.
- The specified visual snapshots do not replace real-device audio verification. A 30-minute foreground/background run remains required to detect missed, duplicated or boundary-shifted clicks.
- The project Issue Tracker is GitHub and the intended triage label is `ready-for-agent`.
