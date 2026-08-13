# Photo to Practice Figma UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the existing vision pipeline with Figma Flow / Photo to Practice: entry chip, source sheet (camera + album), staged generating UI, and detail summary — without a schema change.

**Architecture:** Keep `ImageStepGenerator` → `VisionPracticeClient` → `AIPracticeDraft.normalize` → `PracticeStore.createFromAIDraft`. Encode optional `chords` / `stepMinutes` into `subtitle` and step strings. Replace the RecommendSheet PhotosPicker button with a「拍摄/照片」chip that presents `PhotoPracticeSheet` (source → generating on the same sheet). `PracticeDetailView` reads `AI ·` subtitle for the summary card.

**Tech Stack:** SwiftUI · PhotosUI · UIImagePickerController (still camera) · Swift Testing · existing PracticeStore / SwiftData

## Global Constraints

- Spec: `docs/superpowers/2026-08-06-image-to-practice/specs/2026-08-06-image-to-practice-steps-design.md`
- iOS 18+ · Scheme `foxgita` · new files under `foxgita/` / `foxgitaTests/` auto-join targets
- No SwiftData schema change; reuse `TaskItem.steps` / `StepCoding`
- Camera: 1 photo. Album: max 3. JPEG longest edge ~1280, quality ~0.7, memory only
- Generating progress is display-only; one `chat/completions` request
- Copy: `zh-Hans` via `String(localized:)`
- Unit tests: `xcodebuild -project foxgita.xcodeproj -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:foxgitaTests test`
- Do not log API keys; do not commit secrets
- YAGNI: no streaming, no preview wizard, no schema for chords/step minutes, do not change「完成本次练习」to「开始练习」

## File map

| File | Responsibility |
|---|---|
| `foxgita/Services/AIPracticeDraft.swift` | Optional `chords` / `stepMinutes` on Raw; encode into steps + `subtitleLine` |
| `foxgita/Services/AIPracticePresentation.swift` | Parse `AI ·` subtitle / ` · N 分钟` steps for detail UI |
| `foxgita/Services/PracticeStore.swift` | `createFromAIDraft` uses `draft.subtitleLine` |
| `foxgita/Services/VisionPracticeClient.swift` | Prompt mentions optional `chords` / `stepMinutes` |
| `foxgita/Services/PhotoGenerationProgress.swift` | Display-only stage index + bar fraction |
| `foxgita/Features/Practice/StillImageCameraPicker.swift` | Still-photo `UIImagePickerController` wrapper |
| `foxgita/Features/Practice/PhotoPracticeSheet.swift` | Source picker + generating states |
| `foxgita/Features/Practice/RecommendSheet.swift` | Chip entry; present PhotoPracticeSheet |
| `foxgita/Features/Practice/PracticeDetailView.swift` | AI summary card when subtitle starts with `AI ·` |
| `foxgitaTests/AIPracticeDraftTests.swift` | Encoding tests |
| `foxgitaTests/AIPracticePresentationTests.swift` | Parse tests |
| `foxgitaTests/PhotoGenerationProgressTests.swift` | Stage / fraction tests |
| `foxgitaTests/PracticeStoreTests.swift` | Subtitle with chords |
| `foxgitaUITests/PracticeFlowUITests.swift` | Entry smoke:「拍摄/照片」 |
| `docs/TECHNICAL.md` | Flow note |
| `docs/TEST_PLAN_CLI.md` | UI case label |

---

### Task 1: Encode chords and step minutes in AIPracticeDraft

**Files:**
- Modify: `foxgita/Services/AIPracticeDraft.swift`
- Modify: `foxgita/Services/VisionPracticeClient.swift` (system/user prompt only)
- Test: `foxgitaTests/AIPracticeDraftTests.swift`

**Interfaces:**
- Consumes: existing `PracticeCategory`, `AIPracticeDraft.normalize`
- Produces:
  - `AIPracticeDraft.Raw` adds `chords: [String]?`, `stepMinutes: [Int]?`
  - `AIPracticeDraft` adds `chords: [String]`
  - `var subtitleLine: String` — `AI · {minutes} 分钟` or `AI · {minutes} 分钟 · C · G · Am · F`
  - `normalize` appends ` · {n} 分钟` onto a step when `stepMinutes[i] >= 1`; extra minutes ignored; missing minutes leave the step unchanged

- [ ] **Step 1: Write the failing tests**

Append to `foxgitaTests/AIPracticeDraftTests.swift` (keep existing tests; they still compile because new Raw fields are optional):

```swift
    @Test func normalizeEncodesChordsAndStepMinutes() {
        let raw = AIPracticeDraft.Raw(
            title: "转换",
            category: "chord",
            targetMin: 10,
            steps: ["识别和弦顺序", "分段慢速转换", "完整循环练习"],
            chords: [" C ", "G", "", "Am", "F"],
            stepMinutes: [2, 4, 4, 99]
        )
        let draft = AIPracticeDraft.normalize(raw, fallbackCategory: .left)
        #expect(draft.chords == ["C", "G", "Am", "F"])
        #expect(draft.steps == [
            "识别和弦顺序 · 2 分钟",
            "分段慢速转换 · 4 分钟",
            "完整循环练习 · 4 分钟",
        ])
        #expect(draft.subtitleLine == "AI · 10 分钟 · C · G · Am · F")
    }

    @Test func normalizeOmitsChordsAndMinutesWhenMissing() {
        let raw = AIPracticeDraft.Raw(
            title: "音阶",
            category: "scale",
            targetMin: 8,
            steps: ["上行"],
            chords: nil,
            stepMinutes: [0, 3]
        )
        let draft = AIPracticeDraft.normalize(raw, fallbackCategory: .left)
        #expect(draft.chords.isEmpty)
        #expect(draft.steps == ["上行"])
        #expect(draft.subtitleLine == "AI · 8 分钟")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/AIPracticeDraftTests \
  test
```

Expected: FAIL — `Raw` extra arguments / `chords` / `subtitleLine` missing.

- [ ] **Step 3: Minimal implementation**

Update `AIPracticeDraft` in `foxgita/Services/AIPracticeDraft.swift`:

```swift
struct AIPracticeDraft: Equatable {
    var title: String
    var category: PracticeCategory
    var targetMin: Int
    var steps: [String]
    var chords: [String]

    struct Raw: Decodable, Equatable {
        var title: String?
        var category: String?
        var targetMin: Int?
        var steps: [String]?
        var chords: [String]?
        var stepMinutes: [Int]?
    }

    var subtitleLine: String {
        if chords.isEmpty {
            return String(localized: "AI · \(targetMin) 分钟")
        }
        return String(localized: "AI · \(targetMin) 分钟 · \(chords.joined(separator: " · "))")
    }

    static func normalize(_ raw: Raw, fallbackCategory: PracticeCategory) -> AIPracticeDraft {
        let trimmed = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = trimmed.isEmpty ? String(localized: "未命名练习") : trimmed

        let category: PracticeCategory
        if let rawCat = raw.category, let parsed = PracticeCategory(rawValue: rawCat) {
            category = parsed
        } else {
            category = fallbackCategory
        }

        let minutes: Int
        if let value = raw.targetMin {
            minutes = min(60, max(1, value))
        } else {
            minutes = 10
        }

        var steps = (raw.steps ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if steps.isEmpty {
            steps = [String(localized: "新步骤")]
        } else if steps.count > 12 {
            steps = Array(steps.prefix(12))
        }

        if let stepMinutes = raw.stepMinutes {
            steps = steps.enumerated().map { index, step in
                guard index < stepMinutes.count, stepMinutes[index] >= 1 else { return step }
                return "\(step) · \(stepMinutes[index]) 分钟"
            }
        }

        let chords = (raw.chords ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return AIPracticeDraft(
            title: title,
            category: category,
            targetMin: minutes,
            steps: steps,
            chords: chords
        )
    }
}
```

Existing tests that construct `AIPracticeDraft(...)` without `chords` will fail to compile. Add `chords: []` at those call sites (`PracticeStoreTests.createFromAIDraftPersistsSteps`).

In `VisionPracticeClient.buildBody` user text, add two bullets:

```
- chords: 可选，识别到的和弦名字符串数组（如 C、G、Am）
- stepMinutes: 可选，与 steps 按下标对齐的整数分钟；没有则省略
```

- [ ] **Step 4: Run tests to verify they pass**

Same `xcodebuild` as Step 2, plus:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests/createFromAIDraftPersistsSteps \
  -only-testing:foxgitaTests/VisionPracticeClientTests \
  test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/AIPracticeDraft.swift \
  foxgita/Services/VisionPracticeClient.swift \
  foxgitaTests/AIPracticeDraftTests.swift \
  foxgitaTests/PracticeStoreTests.swift
git commit -m "feat: encode optional chords and step minutes into AIPracticeDraft"
```

---

### Task 2: PracticeStore subtitle from draft.subtitleLine

**Files:**
- Modify: `foxgita/Services/PracticeStore.swift` (`createFromAIDraft`)
- Test: `foxgitaTests/PracticeStoreTests.swift`

**Interfaces:**
- Consumes: `AIPracticeDraft.subtitleLine`
- Produces: persisted `TaskItem.subtitle` equals `draft.subtitleLine`

- [ ] **Step 1: Write the failing test**

Append in `PracticeStoreTests`:

```swift
    @Test func createFromAIDraftEncodesChordsInSubtitle() throws {
        let (store, repo, _) = makeStore(seeded: true)
        let draft = AIPracticeDraft(
            title: "转换",
            category: .chord,
            targetMin: 10,
            steps: ["识别和弦顺序 · 2 分钟"],
            chords: ["C", "G", "Am", "F"]
        )
        let id = try #require(store.createFromAIDraft(draft))
        let task = try #require(try repo.task(id: id))
        #expect(task.subtitle == "AI · 10 分钟 · C · G · Am · F")
        #expect(task.steps == ["识别和弦顺序 · 2 分钟"])
    }
```

- [ ] **Step 2: Run — expect FAIL** (`subtitle` is still `AI · 10 分钟`)

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests/createFromAIDraftEncodesChordsInSubtitle \
  test
```

- [ ] **Step 3: Implement**

In `createFromAIDraft`, replace the subtitle line:

```swift
            subtitle: draft.subtitleLine,
```

- [ ] **Step 4: Run PracticeStoreTests — expect PASS**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests \
  test
```

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeStore.swift foxgitaTests/PracticeStoreTests.swift
git commit -m "feat: persist AI subtitle with encoded chords"
```

---

### Task 3: AIPracticePresentation parse helpers

**Files:**
- Create: `foxgita/Services/AIPracticePresentation.swift`
- Test: `foxgitaTests/AIPracticePresentationTests.swift`

**Interfaces:**
- Consumes: `TaskItem.subtitle` / `steps` strings
- Produces:
  - `static func isAIGenerated(subtitle: String) -> Bool` — `subtitle` has prefix `AI ·`
  - `static func chords(fromSubtitle subtitle: String) -> [String]` — tokens after `AI · {n} 分钟` split by ` · `; empty if none
  - `static func stepParts(_ step: String) -> (title: String, minutes: Int?)` — if suffix matches ` · {n} 分钟`, split; else `(step, nil)`

- [ ] **Step 1: Write failing tests**

Create `foxgitaTests/AIPracticePresentationTests.swift`:

```swift
import Testing
@testable import foxgita

struct AIPracticePresentationTests {
    @Test func detectsAISubtitleAndChords() {
        #expect(AIPracticePresentation.isAIGenerated(subtitle: "AI · 10 分钟 · C · G · Am · F"))
        #expect(AIPracticePresentation.chords(fromSubtitle: "AI · 10 分钟 · C · G · Am · F") == ["C", "G", "Am", "F"])
        #expect(AIPracticePresentation.isAIGenerated(subtitle: "AI · 8 分钟"))
        #expect(AIPracticePresentation.chords(fromSubtitle: "AI · 8 分钟").isEmpty)
        #expect(AIPracticePresentation.isAIGenerated(subtitle: "自定义 · 10 分钟") == false)
        #expect(AIPracticePresentation.chords(fromSubtitle: "自定义 · 10 分钟").isEmpty)
    }

    @Test func splitsStepMinutesSuffix() {
        let timed = AIPracticePresentation.stepParts("识别和弦顺序 · 2 分钟")
        #expect(timed.title == "识别和弦顺序")
        #expect(timed.minutes == 2)
        let plain = AIPracticePresentation.stepParts("慢速按弦")
        #expect(plain.title == "慢速按弦")
        #expect(plain.minutes == nil)
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (`AIPracticePresentation` missing)

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/AIPracticePresentationTests \
  test
```

- [ ] **Step 3: Implement**

Create `foxgita/Services/AIPracticePresentation.swift`:

```swift
import Foundation

enum AIPracticePresentation {
    static func isAIGenerated(subtitle: String) -> Bool {
        subtitle.hasPrefix("AI ·")
    }

    static func chords(fromSubtitle subtitle: String) -> [String] {
        guard isAIGenerated(subtitle: subtitle) else { return [] }
        let marker = "分钟"
        guard let range = subtitle.range(of: marker) else { return [] }
        let rest = subtitle[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard rest.hasPrefix("·") else { return [] }
        return rest.dropFirst()
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func stepParts(_ step: String) -> (title: String, minutes: Int?) {
        let pattern = /^(.+) · (\d+) 分钟$/
        if let match = step.wholeMatch(of: pattern), let minutes = Int(match.2) {
            return (String(match.1), minutes)
        }
        return (step, nil)
    }
}
```

- [ ] **Step 4: Tests PASS**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/AIPracticePresentation.swift foxgitaTests/AIPracticePresentationTests.swift
git commit -m "feat: parse AI subtitle and step-minute suffixes"
```

---

### Task 4: PhotoGenerationProgress (display-only)

**Files:**
- Create: `foxgita/Services/PhotoGenerationProgress.swift`
- Test: `foxgitaTests/PhotoGenerationProgressTests.swift`

**Interfaces:**
- Consumes: elapsed seconds + `completed: Bool`
- Produces:
  - `static let captions = ["已识别和弦与节奏", "正在拆分练习步骤", "即将估算练习时长"]`
  - `static func activeIndex(elapsed: TimeInterval, completed: Bool) -> Int` — 0..<3; completed → 2
  - `static func fraction(elapsed: TimeInterval, completed: Bool) -> Double` — `completed` → 1.0; else `min(0.9, elapsed / 12)`

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Testing
@testable import foxgita

struct PhotoGenerationProgressTests {
    @Test func stagesAdvanceAndComplete() {
        #expect(PhotoGenerationProgress.activeIndex(elapsed: 0, completed: false) == 0)
        #expect(PhotoGenerationProgress.activeIndex(elapsed: 3, completed: false) == 1)
        #expect(PhotoGenerationProgress.activeIndex(elapsed: 6, completed: false) == 2)
        #expect(PhotoGenerationProgress.activeIndex(elapsed: 1, completed: true) == 2)
        #expect(PhotoGenerationProgress.fraction(elapsed: 6, completed: false) == 0.5)
        #expect(PhotoGenerationProgress.fraction(elapsed: 20, completed: false) == 0.9)
        #expect(PhotoGenerationProgress.fraction(elapsed: 1, completed: true) == 1)
        #expect(PhotoGenerationProgress.captions.count == 3)
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PhotoGenerationProgressTests \
  test
```

- [ ] **Step 3: Implement**

```swift
import Foundation

enum PhotoGenerationProgress {
    static let captions = [
        "已识别和弦与节奏",
        "正在拆分练习步骤",
        "即将估算练习时长",
    ]
    static let stageSeconds: TimeInterval = 2.5
    static let fillDuration: TimeInterval = 12

    static func activeIndex(elapsed: TimeInterval, completed: Bool) -> Int {
        if completed { return captions.count - 1 }
        let index = Int(elapsed / stageSeconds)
        return min(captions.count - 1, max(0, index))
    }

    static func fraction(elapsed: TimeInterval, completed: Bool) -> Double {
        if completed { return 1 }
        return min(0.9, max(0, elapsed / fillDuration))
    }
}
```

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PhotoGenerationProgress.swift foxgitaTests/PhotoGenerationProgressTests.swift
git commit -m "feat: add display-only photo generation progress"
```

---

### Task 5: PhotoPracticeSheet + still camera picker

**Files:**
- Create: `foxgita/Features/Practice/StillImageCameraPicker.swift`
- Create: `foxgita/Features/Practice/PhotoPracticeSheet.swift`
- Modify: `foxgita/Services/ImageStepGenerator.swift` — add `var userMessage: String` on `ImageStepGeneratorError` (move copy from RecommendSheet)

**Interfaces:**
- Consumes: `ImageStepGenerator`, `PracticeStore.createFromAIDraft`, `PhotoGenerationProgress`, `LLMCredentialsStore`
- Produces:
  - `StillImageCameraPicker(isPresented:onPicked:onCancel:)` — `sourceType = .camera`, still image → `Data` JPEG
  - `struct PhotoPracticeSheet: View` with:
    - `var fallbackCategory: PracticeCategory`
    - `var baseURL: String`
    - `var model: String`
    - `@Binding var selection: String?`
    - `var onFinished: () -> Void` — parent dismisses RecommendSheet after success
  - States: `.source` / `.generating`
  - Album: `PhotosPicker` max 3; camera: 1 image
  - Generating: timer ~0.1s tick; Close cancels `Task` and returns to `.source`
  - Success: `selection = id`; `onFinished()`
  - Failure: toast; back to `.source`

- [ ] **Step 1: Add `userMessage` and failing compile gate**

Add to `ImageStepGeneratorError`:

```swift
    var userMessage: String {
        switch self {
        case .notConfigured:
            return String(localized: "先去设置里填写 AI 接口")
        case .noImages:
            return String(localized: "请选择图片")
        case .tooManyImages:
            return String(localized: "一次最多 3 张图片")
        case .failed(let vision):
            switch vision {
            case .unauthorized:
                return String(localized: "API Key 无效或无权限")
            case .invalidJSON, .emptyContent:
                return String(localized: "模型返回格式不对，可换模型或重试")
            case .transport:
                return String(localized: "网络异常，请重试")
            case .invalidURL, .httpStatus:
                return String(localized: "生成失败，请稍后重试")
            }
        }
    }
```

In `RecommendSheet.message(for:)` replace the switch body with `return error.userMessage` so copy stays in one place. Build:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 2: StillImageCameraPicker**

Create `foxgita/Features/Practice/StillImageCameraPicker.swift`, same shape as `VideoCameraPicker` but:

```swift
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.cameraCaptureMode = .photo
```

On pick: `info[.originalImage] as? UIImage` → `jpegData(compressionQuality: 0.9)` → `onPicked(Data)`. If camera unavailable, `onCancel()`.

- [ ] **Step 3: PhotoPracticeSheet**

Create `foxgita/Features/Practice/PhotoPracticeSheet.swift`. Layout matches spec §6.2–6.3:

- Header title switches: source「从图片生成练习」/ generating「正在生成练习」
- Source: intro, two cards (拍照 uses `GitaTheme.brand50` + `brand500` title; 相册 uses `bgSubtle`), helper「识别完成后会直接生成练习页，你仍可修改内容」
- Hidden `PhotosPicker` bound to `@State pickerItems`, triggered by 相册 card (`PhotosPicker` overlay or `photosPicker` modifier)
- Generating:「正在识别图片内容」, capsule track + `PhotoGenerationProgress.fraction`, three captions with `activeIndex`, footer「完成后将自动进入生成的练习页」
- `@State private var generateTask: Task<Void, Never>?`
- Close while generating: `generateTask?.cancel()`; `phase = .source`; `isGenerating = false`
- `generate(blobs:)` calls `generator.generate` then `store.createFromAIDraft`; on success set `selection` and `onFinished()`

Use `@Environment(\.dismiss)` for Close on source (dismiss this sheet only). Use `@Environment(PracticeStore.self)`.

Timer: `Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()` while generating.

- [ ] **Step 4: Build**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/ImageStepGenerator.swift \
  foxgita/Features/Practice/StillImageCameraPicker.swift \
  foxgita/Features/Practice/PhotoPracticeSheet.swift \
  foxgita/Features/Practice/RecommendSheet.swift
git commit -m "feat: add PhotoPracticeSheet with camera and album sources"
```

(If RecommendSheet is not yet wired, omit it from this commit and only add the new files + `userMessage`.)

---

### Task 6: RecommendSheet entry chip

**Files:**
- Modify: `foxgita/Features/Practice/RecommendSheet.swift`

**Interfaces:**
- Consumes: `PhotoPracticeSheet`, `LLMCredentialsStore.isConfigured`
- Produces: name-row chip「拍摄/照片」; presents `PhotoPracticeSheet`; removes standalone PhotosPicker / `handlePicked`

- [ ] **Step 1: Replace the input row**

Replace the `HStack` around `TextField` + duration (currently ~lines 66–86) with one integrated bar (`GitaTheme.bgSubtle`, corner 12):

```swift
HStack(spacing: 8) {
    TextField("例如：F 和弦转换", text: $name)
        .padding(.leading, 10)
    Button {
        if credentials.isConfigured(baseURL: llmBaseURL, model: llmModel) {
            showPhotoSheet = true
        } else {
            toast = String(localized: "先去设置里填写 AI 接口")
            hideToastLater()
        }
    } label: {
        Text("拍摄/照片")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(GitaTheme.brand500)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(GitaTheme.brand50)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .disabled(isGenerating)
    Rectangle()
        .fill(GitaTheme.borderSubtle)
        .frame(width: 1, height: 24)
    HStack(spacing: 8) {
        Button { duration = max(5, duration - 5) } label: {
            Text("－").frame(width: 28, height: 28)
        }
        Text("\(duration) 分钟")
            .font(.system(size: 12, weight: .semibold))
            .frame(minWidth: 40)
        Button { duration = min(60, duration + 5) } label: {
            Text("＋").frame(width: 28, height: 28)
        }
    }
    .foregroundStyle(GitaTheme.textSecondary)
    .padding(.trailing, 6)
}
.padding(.vertical, 6)
.background(GitaTheme.bgSubtle)
.clipShape(RoundedRectangle(cornerRadius: 12))
```

Keep「创建练习」as-is (hand-filled only). Delete `PhotosPicker`、「从图片生成练习」、`handlePicked`、`pickerItems`、`generator` if unused.

Add:

```swift
@State private var showPhotoSheet = false
@State private var isGenerating = false
```

`isGenerating` can stay false here if PhotoPracticeSheet owns generating; chip disable can bind to `showPhotoSheet` instead. Prefer `@State private var photoBusy = false` passed via a callback, or simply disable the chip while `showPhotoSheet` is true.

Present:

```swift
.sheet(isPresented: $showPhotoSheet) {
    PhotoPracticeSheet(
        fallbackCategory: category,
        baseURL: llmBaseURL,
        model: llmModel,
        selection: $selection,
        onFinished: {
            showPhotoSheet = false
            dismiss()
        }
    )
    .presentationDetents([.height(340), .medium])
    .presentationDragIndicator(.hidden)
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add foxgita/Features/Practice/RecommendSheet.swift
git commit -m "feat: open PhotoPracticeSheet from RecommendSheet photo chip"
```

---

### Task 7: PracticeDetailView AI summary

**Files:**
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift`
- No new schema

**Interfaces:**
- Consumes: `AIPracticePresentation`
- Produces: when `isAIGenerated(subtitle)`: summary card + optional「识别：」row; step rows show minutes on the right if `stepParts` has minutes. Do not change「完成本次练习」.

- [ ] **Step 1: Replace the meta HStack and insert summary card**

Immediately after the nav bar, inside `content(_ task:)`'s `VStack`, replace:

```swift
                    HStack {
                        Text(task.subtitle)
                        Spacer()
                        Text(task.timeSig)
                    }
```

with:

```swift
                    if AIPracticePresentation.isAIGenerated(subtitle: task.subtitle) {
                        HStack {
                            let chords = AIPracticePresentation.chords(fromSubtitle: task.subtitle)
                            if !chords.isEmpty {
                                Text("识别：\(chords.joined(separator: " · "))")
                            }
                            Spacer()
                            Text("目标 \(task.targetMin) 分钟")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(GitaTheme.textSecondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("已从图片生成")
                                .font(.system(size: 14, weight: .semibold))
                            Text("识别出 \(task.steps.count) 个步骤，可直接修改")
                                .font(.system(size: 12))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        HStack {
                            Text(task.subtitle)
                            Spacer()
                            Text(task.timeSig)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(GitaTheme.textSecondary)
                    }
```

In `stepsCard`, keep `TextField` bound to the full step string (editable as a whole). After the field, if `AIPracticePresentation.stepParts(steps[index]).minutes` is non-nil, show `Text("\(n) 分钟")` in secondary color. Do not add a separate minutes editor.

- [ ] **Step 2: Build**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add foxgita/Features/Practice/PracticeDetailView.swift
git commit -m "feat: show AI photo-practice summary on detail"
```

---

### Task 8: UI smoke + docs

**Files:**
- Modify: `foxgitaUITests/PracticeFlowUITests.swift`
- Modify: `docs/TECHNICAL.md` (§6.3.1)
- Modify: `docs/TEST_PLAN_CLI.md` (UI case label)

**Interfaces:** none new

- [ ] **Step 1: Update UI test**

Replace `testRecommendSheetShowsImageGenerateEntry` body:

```swift
    func testRecommendSheetShowsImageGenerateEntry() {
        let add = app.buttons["添加练习"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.staticTexts["推荐练习"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["拍摄/照片"].waitForExistence(timeout: 5)
            || app.staticTexts["拍摄/照片"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
    }
```

- [ ] **Step 2: Run unit + this UI test**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests \
  test

xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaUITests/PracticeFlowUITests/testRecommendSheetShowsImageGenerateEntry \
  test
```

Expected: PASS.

- [ ] **Step 3: Docs**

In `docs/TECHNICAL.md` §6.3.1, replace the RecommendSheet sentence with: entry is「拍摄/照片」; `PhotoPracticeSheet` offers camera (1) or album (≤3); generating sheet is display-only progress; chords/step minutes encoded in subtitle/step strings; no schema change.

In `docs/TEST_PLAN_CLI.md`, change the UI row to: `testRecommendSheetShowsImageGenerateEntry` | 推荐 Sheet 可见「拍摄/照片」.

- [ ] **Step 4: Commit**

```bash
git add foxgitaUITests/PracticeFlowUITests.swift docs/TECHNICAL.md docs/TEST_PLAN_CLI.md
git commit -m "test: smoke photo chip and document Figma photo-practice flow"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|---|---|
| 拍摄/照片 chip in name row | 6 |
| Unconfigured toast, no second sheet | 6 |
| Source sheet: camera + album copy | 5 |
| Camera 1 / album ≤3 | 5 |
| Generating display progress + cancel | 4, 5 |
| Direct create + dismiss both sheets | 5, 6 |
| chords / stepMinutes encoded, no schema | 1, 2 |
| Detail summary + 识别行 | 3, 7 |
| 完成本次练习 unchanged | 7 (explicit non-change) |
| Error toasts | 5 (`userMessage`) |
| Unit: normalize encoding | 1 |
| Unit: store subtitle | 2 |
| UI smoke 拍摄/照片 | 8 |

## Placeholder / consistency self-review

- `AIPracticeDraft` gains `chords`; Task 2 constructs drafts with `chords:`.
- `subtitleLine` is the single subtitle source for Store.
- `PhotoPracticeSheet.onFinished` dismisses RecommendSheet; Close on source only dismisses Photo sheet.
- Progress captions locked to spec Chinese strings.
- Simulator name: `iPhone 17` (swap if needed).
