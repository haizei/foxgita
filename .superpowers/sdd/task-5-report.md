# Task 5 Report: Sheet, chip, App injection, TECHNICAL.md

## Status
DONE_WITH_CONCERNS

## Branch
`feat/next-session`

## Commit
- `03b0283` — Add Arrange Today chip and a confirm-before-save sheet.

## Summary

Wired Spec 6 UI and App injection only. Recommend Sheet gained「安排今日」; `NextSessionSheet` is a three-phase flow (duration → generating → preview). Generate never writes a task; Confirm is the only `createFromAIDraft` call. `DurationPreferenceSync` is constructed in `foxgitaApp.init()` and injected via `EnvironmentKey` `durationPreferenceSync`. TECHNICAL.md documents the new services and write policy.

## Files

| Action | Path |
|--------|------|
| Created | `foxgita/Features/Practice/NextSessionSheet.swift` |
| Modified | `foxgita/Features/Practice/RecommendSheet.swift` |
| Modified | `foxgita/foxgitaApp.swift` |
| Modified | `docs/TECHNICAL.md` |

Commit scoped to these four paths. Unrelated dirty files left unstaged (`VideoAnalysisView`, `ReviewJobRunner`, architecture html, `Localizable.xcstrings`, deleted media-review docs, `ReviewJobRunnerTests`). `project.pbxproj` not edited (`PBXFileSystemSynchronizedRootGroup`).

## Implementation notes

- `NextSessionSheet` matches the brief: consent gate → `durationSync?.syncActive` → `memoryStore.reload()` → HTTP generate → local citation → preview. Close while generating cancels and returns to duration; disappear cancels and `chooseDisabled()` if the consent sheet is up.
- Recommend chip sits after「拍摄/照片」and before the duration divider. Both chips disable when either nested sheet is presented. Missing credentials toast reuses the existing copy.
- `foxgitaApp` stores `private let durationPreferenceSync` and assigns `self.durationPreferenceSync = durationPreferenceSync` next to `self.memoryStore`. Body injects `.environment(\.durationPreferenceSync, durationPreferenceSync)` next to `.environment(coordinator)`.
- TECHNICAL.md Services tree lists `DurationPreferenceSync` / `NextSessionClient` / `NextSessionGenerator` / `NextSessionCitation` after `AICandidateSync`. MemoryItem write-policy paragraph appends `practice.next_session` 1.0.0 + confirm-before-save + duration upsert + local citation.

## Tests

Destination: `platform=iOS Simulator,name=iPhone 17`.

### Full suite (Step 4)

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

**Result:** compile succeeded (`NextSessionSheet` / `RecommendSheet` / `foxgitaApp` compiled). Full run **TEST FAILED** — 259 tests / 41 suites / 4 issues, all in the known `MockURLProtocol.handler` collision:

- `VisionPracticeClientTests.generateDraftUnauthorized`
- `VisionPracticeClientTests.generateDraftInvalidJSONContent`
- `VisionPracticeClientTests.generateDraftRetriesWithoutResponseFormat`
- `NextSessionClientTests.generateDraftUnregisteredSkillSendsNoRequest`

Did not change `MockURLProtocol`.

### Isolated re-runs

```bash
xcodebuild … -only-testing:foxgitaTests/NextSessionClientTests test
# TEST SUCCEEDED — 6 tests in 1 suite

xcodebuild … -only-testing:foxgitaTests/VisionPracticeClientTests test
# TEST SUCCEEDED — 10 tests in 1 suite
```

Running the two suites in one `xcodebuild` invocation still flakes (crossed handlers). Separate invocations pass.

Manual smoke (not a gate): 加号 → 安排今日 → 选 20 → 生成 → 预览改一步 → 加入今日练习 → 详情打开；关闭预览后首页无新任务.

## Self-review

- Generate path has no `createFromAIDraft`. Confirm builds a trimmed draft and writes once.
- Consent `ensureDecided()` runs before `syncActive` and HTTP.
- Duration chips 15/20/30 plus 5–60 stepper; default from `NextSessionDuration.resolved`.
- Preview citation is `NextSessionCitation.line` from `memoryStore.items`, not model text.
- No V8 / old prompt edits / 3-session planner.

## Concerns

Full `foxgitaTests` is flaky because `NextSessionClientTests` and `VisionPracticeClientTests` share `MockURLProtocol.handler`. Isolated re-runs pass. Out of scope for this task.

## Next Steps (out of scope)

None for Spec 6 UI wiring. Manual smoke remains a human check.

---

## Review fix (Task 5 findings)

**Status:** FIXED

**Commit message:** `Fix next-session consent gating and step row identity.`

### Changes

1. **Consent gate** — `consentedItems` is `memoryStore.items` only when `memoryStore.consent == .enabled`, else `[]`. Duration default uses `parsePreference(consentedItems)` (nil when not enabled). Citation uses the same list, so disabled/undecided shows「通用建议，还没有可参考的练习记忆」.
2. **Step identity** — preview rows use `EditStep` (`UUID` + `text`) instead of `ForEach(editSteps.indices, id: \.self)`. applyDraft / confirm / add / delete use the wrapper.
3. **Minor** — `docs/TECHNICAL.md` SkillRegistryTests row now mentions the fourth skill `practice.next_session` 1.0.0.

### Tests

Destination: `platform=iOS Simulator,name=iPhone 17`.

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/NextSessionCitationTests \
  -only-testing:foxgitaTests/NextSessionGeneratorTests test
```

**Result:** **TEST SUCCEEDED** — 5 tests / 2 suites.

- `NextSessionCitationTests` passed (3 tests)
- `NextSessionGeneratorTests` passed (2 tests)

App target compiled as part of the test build (`CodeSign …/foxgita.app`). Sheet type-checks.
