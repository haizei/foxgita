# Video Intake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add MAIN/01 source picker and ALBUM/02 preview so practice-detail "录视频" can import a Photos video into the existing diagnosis pipeline, without changing the system camera recorder.

**Architecture:** New `AlbumDurationGate` + `AlbumVideoImporter` copy a picked movie into `Documents/Recordings/` with its original extension. `VideoSourceView` presents from the second tap of 录视频; live recording still calls `VideoRecorderService.presentCamera()` after the source cover dismisses. Confirm calls existing `persist()`. No schema change. Reuse C2/04 / C2/05.

**Tech Stack:** SwiftUI · PhotosUI · Photos · AVKit · AVFoundation · Swift Testing · existing `RecordingStore` / `PracticeDetailView.persist`

## Global Constraints

- Spec: `docs/superpowers/2026-08-19-video-intake/specs/2026-08-19-video-intake-design.md`
- iOS 18+ · Scheme `foxgita` · cwd `foxgita/`
- Do not upload `.mov` / `.mp4` / `.m4v`. Diagnosis still sends in-memory JPEGs
- Do not change `VideoRecorderService.ingest`, `VideoDiagnosisGenerator`, Runner, C2/04, C2/05
- Do not add Schema fields
- Album duration gate: `[30, 600]` seconds inclusive; live recording is not gated
- Copy: `zh-Hans` via `String(localized:)`
- Unit test command:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

- Do not log API keys or media bytes; do not commit secrets
- YAGNI: no C2/02, C2/03, C2/06, trim, source field, custom camera

## File map

| File | Responsibility |
|---|---|
| `foxgita/Services/AlbumDurationGate.swift` | `verdict(durationSec:)` for [30, 600] |
| `foxgita/Services/AlbumVideoImporter.swift` | Copy Photos file → Recordings `Clip` |
| `foxgita/Services/RecordingStore.swift` | Add `m4v` to `mediaExtensions` |
| `foxgita/Features/Practice/VideoSourceView.swift` | MAIN/01 + PhotosPicker + permission CTA |
| `foxgita/Features/Practice/AlbumPreviewView.swift` | ALBUM/02 preview + gate + confirm |
| `foxgita/Features/Practice/PracticeDetailView.swift` | Second tap opens source; persist imported clip |
| `foxgita/Localizable.xcstrings` | New zh-Hans keys |
| `docs/TECHNICAL.md` · `docs/TEST_PLAN_CLI.md` | Entry + album copy + new suites |
| `foxgitaTests/AlbumDurationGateTests.swift` | Gate table |
| `foxgitaTests/AlbumVideoImporterTests.swift` | Copy / reject / m4v orphan |

---

### Task 1: AlbumDurationGate

**Files:**
- Create: `foxgita/Services/AlbumDurationGate.swift`
- Test: `foxgitaTests/AlbumDurationGateTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `enum AlbumDurationVerdict: Equatable { case ok, tooShort, tooLong, unknown }`
  - `enum AlbumDurationGate` with `static let minSec = 30`, `static let maxSec = 600`, `static func verdict(durationSec: Int) -> AlbumDurationVerdict`

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/AlbumDurationGateTests.swift`:

```swift
import Testing
@testable import foxgita

struct AlbumDurationGateTests {
    @Test func rejectsBelowThirty() {
        #expect(AlbumDurationGate.verdict(durationSec: 29) == .tooShort)
        #expect(AlbumDurationGate.verdict(durationSec: 1) == .tooShort)
    }

    @Test func acceptsClosedRange() {
        #expect(AlbumDurationGate.verdict(durationSec: 30) == .ok)
        #expect(AlbumDurationGate.verdict(durationSec: 600) == .ok)
        #expect(AlbumDurationGate.verdict(durationSec: 180) == .ok)
    }

    @Test func rejectsAboveTenMinutes() {
        #expect(AlbumDurationGate.verdict(durationSec: 601) == .tooLong)
    }

    @Test func unknownWhenNonPositive() {
        #expect(AlbumDurationGate.verdict(durationSec: 0) == .unknown)
        #expect(AlbumDurationGate.verdict(durationSec: -3) == .unknown)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/AlbumDurationGateTests test
```

Expected: compile error `cannot find 'AlbumDurationGate' in scope`.

- [ ] **Step 3: Implement**

Create `foxgita/Services/AlbumDurationGate.swift`:

```swift
import Foundation

enum AlbumDurationVerdict: Equatable {
    case ok, tooShort, tooLong, unknown
}

enum AlbumDurationGate {
    static let minSec = 30
    static let maxSec = 600

    static func verdict(durationSec: Int) -> AlbumDurationVerdict {
        if durationSec <= 0 { return .unknown }
        if durationSec < minSec { return .tooShort }
        if durationSec > maxSec { return .tooLong }
        return .ok
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Same `xcodebuild` as Step 2. Expected: `TEST SUCCEEDED`, 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/AlbumDurationGate.swift foxgitaTests/AlbumDurationGateTests.swift
git commit -m "feat: gate album videos to 30s–10min"
```

---

### Task 2: AlbumVideoImporter + m4v orphans

**Files:**
- Create: `foxgita/Services/AlbumVideoImporter.swift`
- Modify: `foxgita/Services/RecordingStore.swift` — `mediaExtensions` add `m4v`
- Test: `foxgitaTests/AlbumVideoImporterTests.swift`

**Interfaces:**
- Consumes: `RecordingStore.newFileName(extension:)`, `url(for:)`, `byteSize`, `duration`, `delete`, `removeOrphans`
- Produces:
  - `enum AlbumVideoImporterError: Error, Equatable { case missingSource, unsupportedExtension, copyFailed }`
  - `enum AlbumVideoImporter` with `static let allowedExtensions: Set<String> = ["mov", "mp4", "m4v"]`
  - `@MainActor static func importClip(from source: URL, label: String = "") throws -> VideoRecorderService.Clip`

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/AlbumVideoImporterTests.swift`:

```swift
import Foundation
import Testing
@testable import foxgita

@MainActor
struct AlbumVideoImporterTests {
    @Test func copiesAndKeepsExtension() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("src-\(UUID().uuidString).mp4")
        try Data([0x00, 0x01]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let clip = try AlbumVideoImporter.importClip(from: source, label: "和弦转换")
        defer { RecordingStore.delete(fileName: clip.fileName) }

        #expect(clip.fileName.hasSuffix(".mp4"))
        #expect(clip.bytes == 2)
        #expect(clip.label == "和弦转换")
        #expect(FileManager.default.fileExists(atPath: RecordingStore.url(for: clip.fileName).path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func missingSourceThrows() {
        let missing = URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString).mov")
        #expect(throws: AlbumVideoImporterError.missingSource) {
            try AlbumVideoImporter.importClip(from: missing)
        }
    }

    @Test func rejectsIllegalExtensionAndWritesNothing() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("note-\(UUID().uuidString).txt")
        try Data([0x00]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let before = (try? FileManager.default.contentsOfDirectory(
            at: RecordingStore.directory, includingPropertiesForKeys: nil
        )) ?? []
        #expect(throws: AlbumVideoImporterError.unsupportedExtension) {
            try AlbumVideoImporter.importClip(from: source)
        }
        let after = (try? FileManager.default.contentsOfDirectory(
            at: RecordingStore.directory, includingPropertiesForKeys: nil
        )) ?? []
        #expect(Set(after.map(\.lastPathComponent)) == Set(before.map(\.lastPathComponent)))
    }

    @Test func orphanSweepRemovesUnreferencedM4v() throws {
        let name = "orphan-\(UUID().uuidString).m4v"
        try Data([0x00]).write(to: RecordingStore.url(for: name))
        defer { RecordingStore.delete(fileName: name) }
        let removed = RecordingStore.removeOrphans(referenced: [])
        #expect(removed >= 1)
        #expect(!FileManager.default.fileExists(atPath: RecordingStore.url(for: name).path))
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/AlbumVideoImporterTests test
```

Expected: `cannot find 'AlbumVideoImporter' in scope`. After the type exists but `m4v` is missing, `orphanSweepRemovesUnreferencedM4v` fails (`removed == 0`).

- [ ] **Step 3: Implement**

Create `foxgita/Services/AlbumVideoImporter.swift`:

```swift
import Foundation

enum AlbumVideoImporterError: Error, Equatable {
    case missingSource
    case unsupportedExtension
    case copyFailed
}

enum AlbumVideoImporter {
    static let allowedExtensions: Set<String> = ["mov", "mp4", "m4v"]

    @MainActor
    static func importClip(from source: URL, label: String = "") throws -> VideoRecorderService.Clip {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw AlbumVideoImporterError.missingSource
        }
        let ext = source.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw AlbumVideoImporterError.unsupportedExtension
        }
        let name = RecordingStore.newFileName(extension: ext)
        let dest = RecordingStore.url(for: name)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            return VideoRecorderService.Clip(
                id: UUID().uuidString,
                fileName: name,
                bytes: RecordingStore.byteSize(of: dest),
                durationSec: RecordingStore.duration(of: dest),
                createdAt: Date(),
                label: label.isEmpty ? String(localized: "视频") : label
            )
        } catch {
            RecordingStore.delete(fileName: name)
            throw AlbumVideoImporterError.copyFailed
        }
    }
}
```

In `foxgita/Services/RecordingStore.swift`, change:

```swift
private static let mediaExtensions: Set<String> = ["m4a", "mov", "mp4"]
```

to:

```swift
private static let mediaExtensions: Set<String> = ["m4a", "mov", "mp4", "m4v"]
```

- [ ] **Step 4: Run tests — expect PASS**

Same command as Step 2. Expected: `TEST SUCCEEDED`, 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/AlbumVideoImporter.swift \
  foxgita/Services/RecordingStore.swift \
  foxgitaTests/AlbumVideoImporterTests.swift
git commit -m "feat: copy album videos into Recordings"
```

---

### Task 3: Source + preview UI and practice-detail wiring

**Files:**
- Create: `foxgita/Features/Practice/VideoSourceView.swift`
- Create: `foxgita/Features/Practice/AlbumPreviewView.swift`
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift` — second tap presents source; `onDismiss` may present camera; imported clip goes through `persist`
- Modify: `foxgita/Localizable.xcstrings` — add the new keys listed below

**Interfaces:**
- Consumes: `AlbumDurationGate.verdict`, `AlbumVideoImporter.importClip`, `VideoRecorderService.presentCamera`, `persist(_:task:)`
- Produces:
  - `struct AlbumPreviewItem: Identifiable` with `id: UUID`, `url: URL`, `displayName: String`, `durationSec: Int`
  - `struct VideoSourceView` with `taskTitle: String`, `onDismiss: () -> Void`, `onStartCamera: () -> Void`, `onImported: (VideoRecorderService.Clip) -> Void`, `onToast: (String) -> Void`
  - `struct AlbumPreviewView` with `item: AlbumPreviewItem`, `onBack: () -> Void`, `onReselect: () -> Void`, `onConfirm: () -> Void`

- [ ] **Step 1: Add `AlbumPreviewView.swift`**

```swift
import AVKit
import SwiftUI

struct AlbumPreviewItem: Identifiable {
    let id: UUID
    let url: URL
    let displayName: String
    let durationSec: Int

    init(id: UUID = UUID(), url: URL, displayName: String, durationSec: Int) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.durationSec = durationSec
    }
}

struct AlbumPreviewView: View {
    let item: AlbumPreviewItem
    var onBack: () -> Void
    var onReselect: () -> Void
    var onConfirm: () -> Void

    private var verdict: AlbumDurationVerdict {
        AlbumDurationGate.verdict(durationSec: item.durationSec)
    }

    private var canConfirm: Bool { verdict == .ok }

    private var durationLabel: String {
        let seconds = max(0, item.durationSec)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var gateMessage: String? {
        switch verdict {
        case .ok: return nil
        case .tooShort: return String(localized: "这段视频太短，证据不足，请选择至少 30 秒")
        case .tooLong: return String(localized: "这段视频超过 10 分钟，请换一段更短的")
        case .unknown: return String(localized: "无法读取时长")
        }
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                HStack {
                    Button(String(localized: "返回"), action: onBack)
                        .font(.system(size: 14))
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(minWidth: 40, alignment: .leading)
                    Text(String(localized: "预览确认"))
                        .font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity)
                    Color.clear.frame(width: 40, height: 1)
                }
                .frame(minHeight: 56)
                .padding(.horizontal, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(item.displayName)
                            .font(.system(size: 16, weight: .semibold))
                        Text(durationLabel)
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                        VideoPlayer(player: AVPlayer(url: item.url))
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        if let gateMessage {
                            Text(gateMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(GitaTheme.statusError)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                HStack(spacing: 10) {
                    Button(String(localized: "重新选择"), action: onReselect)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GitaTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay(Capsule().stroke(GitaTheme.borderSubtle, lineWidth: 1))
                    Button(String(localized: "开始分析"), action: onConfirm)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GitaTheme.brandOn)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(canConfirm ? GitaTheme.brand500 : GitaTheme.borderInactive)
                        .clipShape(Capsule())
                        .disabled(!canConfirm)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }
}
```

- [ ] **Step 2: Add `VideoSourceView.swift`**

```swift
import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct VideoSourceView: View {
    let taskTitle: String
    var onDismiss: () -> Void
    var onStartCamera: () -> Void
    var onImported: (VideoRecorderService.Clip) -> Void
    var onToast: (String) -> Void

    private enum Mode { case camera, album }

    @State private var mode: Mode = .camera
    @State private var pickerItem: PhotosPickerItem?
    @State private var preview: AlbumPreviewItem?
    @State private var albumDenied = false

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                HStack {
                    Button(String(localized: "返回"), action: onDismiss)
                        .font(.system(size: 14))
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(minWidth: 40, alignment: .leading)
                    Text(String(localized: "选择视频来源"))
                        .font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity)
                    Color.clear.frame(width: 40, height: 1)
                }
                .frame(minHeight: 56)
                .padding(.horizontal, 16)

                Text(taskTitle)
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                SegmentedPills(
                    titles: [String(localized: "现场录像"), String(localized: "上传相册")],
                    selection: Binding(
                        get: { mode == .camera ? 0 : 1 },
                        set: { mode = $0 == 0 ? .camera : .album }
                    )
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)

                card
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                Spacer()

                bottomButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .onAppear { refreshAlbumAuth() }
        .fullScreenCover(item: $preview) { item in
            AlbumPreviewView(
                item: item,
                onBack: { preview = nil },
                onReselect: {
                    preview = nil
                    pickerItem = nil
                },
                onConfirm: { confirm(item) }
            )
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPicked(item) }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == .camera ? String(localized: "现场录像") : String(localized: "上传相册"))
                .font(.system(size: 17, weight: .bold))
            Text(
                mode == .camera
                    ? String(localized: "立即拍摄本次练习，完成后进行分段诊断")
                    : String(localized: "选择已有练习视频，完成后进行分段诊断")
            )
            .font(.system(size: 13))
            .foregroundStyle(GitaTheme.textSecondary)
            if mode == .album, albumDenied {
                Button(String(localized: "前往系统设置")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GitaTheme.brand500)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }

    @ViewBuilder
    private var bottomButton: some View {
        if mode == .camera {
            Button(String(localized: "开始录像"), action: onStartCamera)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GitaTheme.brandOn)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(GitaTheme.brand500)
                .clipShape(Capsule())
        } else if albumDenied {
            Button(String(localized: "前往系统设置")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(GitaTheme.brandOn)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(GitaTheme.brand500)
            .clipShape(Capsule())
        } else {
            PhotosPicker(selection: $pickerItem, matching: .videos) {
                Text(String(localized: "选择视频"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(GitaTheme.brand500)
                    .clipShape(Capsule())
            }
        }
    }

    private func refreshAlbumAuth() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        albumDenied = status == .denied || status == .restricted
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        do {
            guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                onToast(String(localized: "无法读取该视频"))
                return
            }
            let duration = RecordingStore.duration(of: movie.url)
            let name = movie.url.lastPathComponent
            preview = AlbumPreviewItem(
                url: movie.url,
                displayName: name.isEmpty ? String(localized: "相册视频") : name,
                durationSec: duration
            )
        } catch {
            onToast(String(localized: "无法读取该视频"))
        }
    }

    private func confirm(_ item: AlbumPreviewItem) {
        do {
            let clip = try AlbumVideoImporter.importClip(from: item.url, label: taskTitle)
            preview = nil
            onImported(clip)
        } catch {
            onToast(String(localized: "无法保存视频"))
        }
    }
}

struct ImportedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            Self(url: received.file)
        }
    }
}
```

- [ ] **Step 3: Wire `PracticeDetailView`**

Add state next to the other `@State` properties:

```swift
@State private var isSourcePresented = false
@State private var pendingCamera = false
```

Replace the video tool action that calls `video.presentCamera()` with:

```swift
isSourcePresented = true
```

(Keep the first-tap `toolMode = .video` branch unchanged.)

After the existing camera `fullScreenCover`, add:

```swift
.fullScreenCover(isPresented: $isSourcePresented, onDismiss: {
    if pendingCamera {
        pendingCamera = false
        video.presentCamera()
    }
}) {
    VideoSourceView(
        taskTitle: task?.title ?? "",
        onDismiss: { isSourcePresented = false },
        onStartCamera: {
            pendingCamera = true
            isSourcePresented = false
        },
        onImported: { clip in
            if let task { persist(audioClip(clip), task: task) }
            isSourcePresented = false
        },
        onToast: { show($0) }
    )
}
```

- [ ] **Step 4: Add Localizable keys**

In `foxgita/Localizable.xcstrings` `strings` object, add empty catalogs (key is the zh-Hans source) for:

`选择视频来源`、`现场录像`、`上传相册`、`立即拍摄本次练习，完成后进行分段诊断`、`选择已有练习视频，完成后进行分段诊断`、`开始录像`、`选择视频`、`前往系统设置`、`预览确认`、`重新选择`、`开始分析`、`这段视频太短，证据不足，请选择至少 30 秒`、`这段视频超过 10 分钟，请换一段更短的`、`无法读取时长`、`无法读取该视频`、`相册视频`

Insert them in alphabetical-ish positions if easy; Xcode accepts any order. Format:

```json
"选择视频来源" : {

},
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add foxgita/Features/Practice/VideoSourceView.swift \
  foxgita/Features/Practice/AlbumPreviewView.swift \
  foxgita/Features/Practice/PracticeDetailView.swift \
  foxgita/Localizable.xcstrings
git commit -m "feat: present video source picker and album preview"
```

---

### Task 4: Docs

**Files:**
- Modify: `docs/TECHNICAL.md` — 录视频入口、§6.3.3 增加相册拷贝
- Modify: `docs/TEST_PLAN_CLI.md` — add the two new suites

- [ ] **Step 1: TECHNICAL.md**

In the 近期增量 line, append `、录像来源选择与相册导入`.

Change the two “录视频” behavior rows from “打开系统相机” to: 第 2 次点打开来源页；现场录像仍 `presentCamera()`；相册经预览确认后拷进 Recordings 再 `persist`。

In §6.3.3 after step 1, add a bullet:

相册：`PhotosPicker` → `AlbumPreviewView` 时长门 `[30, 600]` 秒 → `AlbumVideoImporter` 按原扩展名拷贝 → 同一 `persist` / C2/04。系统相册原片不删。`RecordingStore.mediaExtensions` 含 `m4v`。

- [ ] **Step 2: TEST_PLAN_CLI.md**

Add rows:

| `AlbumDurationGateTests` | 29/0 拒绝、30/600 通过、601 拒绝 |
| `AlbumVideoImporterTests` | 保留扩展名、缺文件、非法扩展名不写盘、`.m4v` 孤儿清理 |

- [ ] **Step 3: Run unit tests**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: `TEST SUCCEEDED`. Existing diagnosis / runner / audio suites stay green.

- [ ] **Step 4: Commit**

```bash
git add docs/TECHNICAL.md docs/TEST_PLAN_CLI.md
git commit -m "docs: record album video intake"
```

---

## Spec coverage

| Spec | Task |
|---|---|
| MAIN/01 second tap | 3 |
| Live camera unchanged after source dismiss | 3 |
| ALBUM/02 + [30, 600] | 1, 3 |
| Copy keep extension, no upload | 2 |
| persist / C2/04 reuse | 3 |
| m4v orphans | 2 |
| Permission CTA, no full S1 | 3 |
| No schema / no C2/06 | all (omitted) |
| Docs | 4 |
