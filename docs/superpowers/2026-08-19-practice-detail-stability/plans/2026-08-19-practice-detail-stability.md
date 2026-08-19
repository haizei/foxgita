# Practice Detail Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix practice-detail BPM ±1, make pause/resume actually restart the metronome, and show all saved audio/video for the task when the user re-enters.

**Architecture:** Extract `PracticeClipQuery` (pure filter/sort/dedupe) and `RecordingStore.fileExists`. Split metronome graph setup from `engine.start()`. `AudioSessionCoordinator.acquire` rolls back its need count on failure. `PracticeDetailView` binds those cores: ±1 buttons, start-fails-then-timer-stays-stopped, historical clips, absolute timestamps, missing-file badge, empty states. No schema change. `openSessionId` still decides where new clips are written, not what the list shows.

**Tech Stack:** SwiftUI · SwiftData · AVAudioEngine · AVAudioSession · Swift Testing · existing `PracticeTimer` / `PracticeStore` / `MediaReviewMedia`

## Global Constraints

- Spec: `docs/superpowers/2026-08-19-practice-detail-stability/specs/2026-08-19-practice-detail-stability-design.md`
- iOS 18+ · Scheme `foxgita` · cwd `foxgita/` (git root)
- Copy: `zh-Hans` via `String(localized:)`
- Do not change Schema, `beginOpenSession` / `appendRecording` / `updateOpenSession` semantics
- Do not add in-practice playback, long-press BPM, ±5, session grouping, or pagination
- Do not set `engineStarted = false` as the only metronome fix (that re-attaches the player node)
- Do not log API keys, sandbox absolute paths, or raw `NSError` in user-visible copy
- Unit test command:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

- Targets use `PBXFileSystemSynchronizedRootGroup`: new files under `foxgita/` and `foxgitaTests/` are picked up automatically. Do not edit `project.pbxproj`.

## File map

| File | Responsibility |
|---|---|
| `foxgita/Services/PracticeClipQuery.swift` | Descriptor + `visible` + absolute timestamp |
| `foxgita/Services/RecordingStore.swift` | Add `fileExists(fileName:)` |
| `foxgita/Services/AudioSessionCoordinator.swift` | Injected `apply`, acquire rollback, `count(for:)` |
| `foxgita/Services/MetronomeEngine.swift` | Graph once; `start() throws`; session injection |
| `foxgita/Features/Practice/PracticeDetailView.swift` | ±1, togglePlay, historical list, empty, missing |
| `foxgita/Features/Record/RecordDetailView.swift` | Play / diagnosis guard |
| `foxgita/Services/AudioRecorderService.swift` | `AudioPlayerService` missing-file guard |
| `foxgita/Features/Practice/VideoDiagnosisView.swift` | `DiagnosisClipPlayer.load` missing-file guard |
| `foxgita/Localizable.xcstrings` | New / renamed strings |
| `docs/TECHNICAL.md` · `docs/TEST_PLAN_CLI.md` | Engine restart + new suites |
| `foxgitaTests/PracticeClipQueryTests.swift` | Filter / sort / dedupe / timestamp |
| `foxgitaTests/RecordingStoreTests.swift` | `fileExists` true/false |
| `foxgitaTests/AudioSessionCoordinatorTests.swift` | Rollback + playAndRecord preference |
| `foxgitaTests/MetronomeEngineTests.swift` | BPM clamp, start throw, stop/start, pump |

YAGNI: no `AudioGraph` protocol, no clip grouping types, no second card style.

---

### Task 1: PracticeClipQuery

**Files:**
- Create: `foxgita/Services/PracticeClipQuery.swift`
- Test: `foxgitaTests/PracticeClipQueryTests.swift`

**Interfaces:**
- Consumes: `MediaReviewMedia.isVideo(fileName:)`
- Produces:
  - `struct PracticeClipDescriptor: Equatable` with `id: String`, `fileName: String`, `createdAt: Date`, `deletedAt: Date?`
  - `enum PracticeClipQuery` with `static func visible(clips: [PracticeClipDescriptor], videoMode: Bool) -> [PracticeClipDescriptor]`
  - `static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String`

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/PracticeClipQueryTests.swift`:

```swift
import Foundation
import Testing
@testable import foxgita

struct PracticeClipQueryTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_100)
    private let t2 = Date(timeIntervalSince1970: 1_700_000_200)

    private func clip(
        id: String, fileName: String, createdAt: Date, deletedAt: Date? = nil
    ) -> PracticeClipDescriptor {
        PracticeClipDescriptor(
            id: id, fileName: fileName, createdAt: createdAt, deletedAt: deletedAt
        )
    }

    @Test func dropsDeleted() {
        let clips = [
            clip(id: "a", fileName: "a.m4a", createdAt: t1),
            clip(id: "b", fileName: "b.m4a", createdAt: t2, deletedAt: t2),
        ]
        let visible = PracticeClipQuery.visible(clips: clips, videoMode: false)
        #expect(visible.map(\.id) == ["a"])
    }

    @Test func splitsAudioAndVideo() {
        let clips = [
            clip(id: "a", fileName: "a.m4a", createdAt: t1),
            clip(id: "v", fileName: "v.mov", createdAt: t2),
            clip(id: "p", fileName: "p.mp4", createdAt: t0),
        ]
        #expect(PracticeClipQuery.visible(clips: clips, videoMode: false).map(\.id) == ["a"])
        #expect(PracticeClipQuery.visible(clips: clips, videoMode: true).map(\.id) == ["v", "p"])
    }

    @Test func sortsNewestFirstAcrossSessions() {
        let clips = [
            clip(id: "old", fileName: "old.m4a", createdAt: t0),
            clip(id: "new", fileName: "new.m4a", createdAt: t2),
            clip(id: "mid", fileName: "mid.m4a", createdAt: t1),
        ]
        #expect(PracticeClipQuery.visible(clips: clips, videoMode: false).map(\.id) == ["new", "mid", "old"])
    }

    @Test func dedupesByIdKeepingFirstAfterSort() {
        let clips = [
            clip(id: "same", fileName: "a.m4a", createdAt: t0),
            clip(id: "same", fileName: "a.m4a", createdAt: t2),
        ]
        let visible = PracticeClipQuery.visible(clips: clips, videoMode: false)
        #expect(visible.map(\.id) == ["same"])
        #expect(visible.first?.createdAt == t2)
    }

    @Test func timestampUsesChineseAbsoluteDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: 2026, month: 8, day: 16, hour: 14, minute: 32
        ))!
        #expect(
            PracticeClipQuery.timestamp(date, timeZone: calendar.timeZone) == "8月16日 14:32"
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeClipQueryTests test
```

Expected: FAIL, `PracticeClipQuery` not in scope.

- [ ] **Step 3: Write minimal implementation**

Create `foxgita/Services/PracticeClipQuery.swift`:

```swift
import Foundation

struct PracticeClipDescriptor: Equatable {
    var id: String
    var fileName: String
    var createdAt: Date
    var deletedAt: Date?
}

enum PracticeClipQuery {
    static func visible(
        clips: [PracticeClipDescriptor], videoMode: Bool
    ) -> [PracticeClipDescriptor] {
        var seen = Set<String>()
        return clips
            .filter { $0.deletedAt == nil }
            .filter { MediaReviewMedia.isVideo(fileName: $0.fileName) == videoMode }
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seen.insert($0.id).inserted }
    }

    static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeClipQueryTests test
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeClipQuery.swift foxgitaTests/PracticeClipQueryTests.swift
git commit -m "feat: query practice clips across sessions by type and date"
```

---

### Task 2: RecordingStore.fileExists

**Files:**
- Modify: `foxgita/Services/RecordingStore.swift`
- Test: `foxgitaTests/RecordingStoreTests.swift`

**Interfaces:**
- Consumes: `RecordingStore.url(for:)`
- Produces: `static func fileExists(fileName: String) -> Bool`

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/RecordingStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import foxgita

struct RecordingStoreTests {
    @Test func fileExistsAfterWriteAndDelete() throws {
        let name = RecordingStore.newFileName()
        let url = RecordingStore.url(for: name)
        try Data([0x01, 0x02]).write(to: url)
        defer { RecordingStore.delete(fileName: name) }
        #expect(RecordingStore.fileExists(fileName: name))
        RecordingStore.delete(fileName: name)
        #expect(!RecordingStore.fileExists(fileName: name))
    }

    @Test func fileExistsIsFalseForMissingName() {
        #expect(!RecordingStore.fileExists(fileName: "rec-missing-does-not-exist.m4a"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/RecordingStoreTests test
```

Expected: FAIL, `fileExists` not found.

- [ ] **Step 3: Write minimal implementation**

In `foxgita/Services/RecordingStore.swift`, immediately after `url(for:)`:

```swift
    static func fileExists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName).path)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/RecordingStoreTests test
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/RecordingStore.swift foxgitaTests/RecordingStoreTests.swift
git commit -m "feat: expose RecordingStore.fileExists for missing clip cards"
```

---

### Task 3: AudioSessionCoordinator acquire rollback

**Files:**
- Modify: `foxgita/Services/AudioSessionCoordinator.swift` (replace the type; keep Need, interruption, `shared`)
- Test: `foxgitaTests/AudioSessionCoordinatorTests.swift`

**Interfaces:**
- Consumes: `AVAudioSession` when `apply` is nil
- Produces:
  - `init(apply: (@MainActor () throws -> Void)? = nil)` — nil means the real session
  - `func acquire(_ need: Need) throws` increments, then apply; on throw, rollback that increment
  - `func release(_ need: Need)` unchanged semantics
  - `func count(for need: Need) -> Int`
  - `var prefersPlayAndRecord: Bool` — true when record count > 0

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/AudioSessionCoordinatorTests.swift`:

```swift
import Foundation
import Testing
@testable import foxgita

private struct ApplyBoom: Error {}

@MainActor
struct AudioSessionCoordinatorTests {
    @Test func acquireFailureRollsBackCount() {
        let coordinator = AudioSessionCoordinator(apply: { throw ApplyBoom() })
        #expect(throws: ApplyBoom.self) {
            try coordinator.acquire(.playback)
        }
        #expect(coordinator.count(for: .playback) == 0)
        #expect(coordinator.count(for: .record) == 0)
    }

    @Test func pairedAcquireReleaseClearsNeeds() throws {
        let coordinator = AudioSessionCoordinator(apply: { })
        try coordinator.acquire(.playback)
        #expect(coordinator.count(for: .playback) == 1)
        coordinator.release(.playback)
        #expect(coordinator.count(for: .playback) == 0)
    }

    @Test func recordNeedKeepsPlayAndRecordWhenPlaybackAcquired() throws {
        let coordinator = AudioSessionCoordinator(apply: { })
        try coordinator.acquire(.record)
        try coordinator.acquire(.playback)
        #expect(coordinator.prefersPlayAndRecord)
        coordinator.release(.playback)
        #expect(coordinator.prefersPlayAndRecord)
        coordinator.release(.record)
        #expect(!coordinator.prefersPlayAndRecord)
    }

    @Test func overlappingPlaybackNeeds() throws {
        let coordinator = AudioSessionCoordinator(apply: { })
        try coordinator.acquire(.playback)
        try coordinator.acquire(.playback)
        #expect(coordinator.count(for: .playback) == 2)
        coordinator.release(.playback)
        #expect(coordinator.count(for: .playback) == 1)
        coordinator.release(.playback)
        #expect(coordinator.count(for: .playback) == 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/AudioSessionCoordinatorTests test
```

Expected: FAIL (`init(apply:)` / `count(for:)` missing). Do not change production `shared` callers yet.

- [ ] **Step 3: Write implementation**

Replace `foxgita/Services/AudioSessionCoordinator.swift` with:

```swift
import AVFoundation
import Foundation

@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    enum Need: Hashable {
        case playback
        case record
    }

    private var needCounts: [Need: Int] = [:]
    private var observer: NSObjectProtocol?
    private let applyOverride: (@MainActor () throws -> Void)?

    var onInterruption: (() -> Void)?

    var prefersPlayAndRecord: Bool { needCounts[.record, default: 0] > 0 }

    init(apply: (@MainActor () throws -> Void)? = nil) {
        applyOverride = apply
        guard apply == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleInterruption(note) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func count(for need: Need) -> Int { needCounts[need, default: 0] }

    func acquire(_ need: Need) throws {
        needCounts[need, default: 0] += 1
        do {
            try applyCategory()
        } catch {
            rollback(need)
            throw error
        }
    }

    func release(_ need: Need) {
        guard let count = needCounts[need], count > 0 else { return }
        if count == 1 {
            needCounts.removeValue(forKey: need)
        } else {
            needCounts[need] = count - 1
        }
        guard needCounts.isEmpty else {
            try? applyCategory()
            return
        }
        guard applyOverride == nil else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func rollback(_ need: Need) {
        guard let count = needCounts[need], count > 0 else { return }
        if count == 1 {
            needCounts.removeValue(forKey: need)
        } else {
            needCounts[need] = count - 1
        }
    }

    private func applyCategory() throws {
        if let applyOverride {
            try applyOverride()
            return
        }
        let session = AVAudioSession.sharedInstance()
        if needCounts[.record, default: 0] > 0 {
            try session.setCategory(
                .playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers]
            )
        } else {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try session.setActive(true)
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        guard type == .began else { return }
        needCounts.removeAll()
        onInterruption?()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/AudioSessionCoordinatorTests test
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/AudioSessionCoordinator.swift foxgitaTests/AudioSessionCoordinatorTests.swift
git commit -m "fix: roll back audio session need counts when apply fails"
```

---

### Task 4: MetronomeEngine start throws and graph split

**Files:**
- Modify: `foxgita/Services/MetronomeEngine.swift`
- Test: `foxgitaTests/MetronomeEngineTests.swift`

**Interfaces:**
- Consumes: `AudioSessionCoordinator.acquire/release(.playback)`, `count(for:)`
- Produces:
  - `enum MetronomeError: Error, Equatable { case engineNotRunning }`
  - `init(session: AudioSessionCoordinator = .shared)`
  - `func start() throws` — `isPlaying` becomes true only after `engine.isRunning`
  - `func stop()` — stops pump and player, does **not** `engine.stop()`, does **not** detach nodes
  - `var isEngineRunning: Bool { engine.isRunning }` (internal, for tests)
  - `var hasPump: Bool { pump != nil }` (internal, for tests)
  - `setBpm` / `bump` unchanged (`40...200`)

`fill()` currently `guard isPlaying`. Set `isPlaying = true` after `engine.isRunning` is confirmed and `player.play()` has been called, immediately before `fill()`. If `start()` throws, `isPlaying` stays false and a successful acquire is released.

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/MetronomeEngineTests.swift`:

```swift
import Foundation
import Testing
@testable import foxgita

private struct ApplyBoom: Error {}

@MainActor
struct MetronomeEngineTests {
    @Test func bumpClampsAndStepsByOne() {
        let metronome = MetronomeEngine(session: AudioSessionCoordinator(apply: { }))
        #expect(metronome.bpm == 80)
        metronome.bump(1)
        metronome.bump(1)
        metronome.bump(1)
        #expect(metronome.bpm == 83)
        metronome.bump(-1)
        #expect(metronome.bpm == 82)
        metronome.setBpm(39)
        #expect(metronome.bpm == 40)
        metronome.bump(-1)
        #expect(metronome.bpm == 40)
        metronome.setBpm(201)
        #expect(metronome.bpm == 200)
        metronome.bump(1)
        #expect(metronome.bpm == 200)
    }

    @Test func startFailureLeavesIdleAndReleasesSession() {
        let session = AudioSessionCoordinator(apply: { throw ApplyBoom() })
        let metronome = MetronomeEngine(session: session)
        #expect(throws: ApplyBoom.self) {
            try metronome.start()
        }
        #expect(!metronome.isPlaying)
        #expect(!metronome.hasPump)
        #expect(session.count(for: .playback) == 0)
    }

    @Test func startStopStartRunsEngineWithoutSecondPump() throws {
        let metronome = MetronomeEngine()
        try metronome.start()
        #expect(metronome.isPlaying)
        #expect(metronome.isEngineRunning)
        #expect(metronome.hasPump)
        metronome.stop()
        #expect(!metronome.isPlaying)
        #expect(!metronome.hasPump)
        try metronome.start()
        #expect(metronome.isPlaying)
        #expect(metronome.isEngineRunning)
        #expect(metronome.hasPump)
        metronome.stop()
        #expect(!metronome.hasPump)
    }

    @Test func stopIsIdempotent() {
        let metronome = MetronomeEngine(session: AudioSessionCoordinator(apply: { }))
        metronome.stop()
        metronome.stop()
        #expect(!metronome.isPlaying)
        #expect(!metronome.hasPump)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MetronomeEngineTests test
```

Expected: FAIL (`init(session:)` / `start() throws` missing). `bumpClampsAndStepsByOne` may already pass against current `setBpm` if the type constructs; if `init(session:)` is missing the whole file fails to compile.

- [ ] **Step 3: Replace `foxgita/Services/MetronomeEngine.swift` entirely**

```swift
import AVFoundation
import Foundation
import os

enum MetronomeError: Error, Equatable {
    case engineNotRunning
}

private let metronomeLog = Logger(subsystem: "com.haizei.foxgita", category: "metronome")

/// Sample-accurate metronome. Clicks are scheduled onto exact audio frames a
/// short distance ahead of the audio clock, so beat spacing comes from the
/// audio hardware rather than from when the scheduling timer happens to fire.
@Observable
final class MetronomeEngine {
    private(set) var isPlaying = false
    private(set) var bpm = 80

    private static let lead = 0.15
    private static let pumpInterval = 0.05

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let format = AVAudioFormat(
        standardFormatWithSampleRate: 44_100, channels: 1
    )!
    @ObservationIgnored private let session: AudioSessionCoordinator
    @ObservationIgnored private var accentClick: AVAudioPCMBuffer?
    @ObservationIgnored private var beatClick: AVAudioPCMBuffer?
    @ObservationIgnored private var pump: Timer?
    @ObservationIgnored private var nextBeatFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var beatIndex = 0
    @ObservationIgnored private var graphConfigured = false
    @ObservationIgnored private var runToken = 0

    var hapticsEnabled = true

    var isEngineRunning: Bool { engine.isRunning }
    var hasPump: Bool { pump != nil }

    init(session: AudioSessionCoordinator = .shared) {
        self.session = session
    }

    func setBpm(_ value: Int) {
        let clamped = min(200, max(40, value))
        guard clamped != bpm else { return }
        bpm = clamped
    }

    func bump(_ delta: Int) { setBpm(bpm + delta) }

    func start() throws {
        guard !isPlaying else { return }
        var acquired = false
        do {
            try session.acquire(.playback)
            acquired = true
            configureGraphIfNeeded()
            if !engine.isRunning {
                try engine.start()
            }
            guard engine.isRunning else { throw MetronomeError.engineNotRunning }
            player.stop()
            beatIndex = 0
            runToken += 1
            player.play()
            nextBeatFrame = currentFrame() + frames(0.1)
            isPlaying = true
            fill()
            pump = Timer.scheduledTimer(withTimeInterval: Self.pumpInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.fill() }
            }
            if let pump { RunLoop.main.add(pump, forMode: .common) }
            metronomeLog.debug(
                "start bpm=\(self.bpm, privacy: .public) running=\(self.engine.isRunning, privacy: .public)"
            )
        } catch {
            isPlaying = false
            pump?.invalidate()
            pump = nil
            if acquired { session.release(.playback) }
            metronomeLog.error("start failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func stop() {
        guard isPlaying || pump != nil else { return }
        pump?.invalidate()
        pump = nil
        player.stop()
        isPlaying = false
        beatIndex = 0
        runToken += 1
        session.release(.playback)
        metronomeLog.debug(
            "stop running=\(self.engine.isRunning, privacy: .public) other=\(AVAudioSession.sharedInstance().isOtherAudioPlaying, privacy: .public)"
        )
    }

    func toggle() {
        if isPlaying { stop() } else { try? start() }
    }

    private func configureGraphIfNeeded() {
        guard !graphConfigured else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        accentClick = Self.makeClick(format: format, frequency: 1_000, amplitude: 0.9)
        beatClick = Self.makeClick(format: format, frequency: 800, amplitude: 0.5)
        graphConfigured = true
    }

    private func fill() {
        guard isPlaying, let accent = accentClick, let beat = beatClick else { return }
        let now = currentFrame()
        if nextBeatFrame < now {
            nextBeatFrame = now + frames(0.05)
            beatIndex = 0
        }
        let horizon = now + frames(Self.lead)
        let step = frames(60.0 / Double(bpm))
        while nextBeatFrame <= horizon {
            let isDownbeat = beatIndex % 4 == 0
            player.scheduleBuffer(
                isDownbeat ? accent : beat,
                at: AVAudioTime(sampleTime: nextBeatFrame, atRate: format.sampleRate),
                options: [],
                completionHandler: nil
            )
            if isDownbeat { scheduleDownbeatHaptic(at: nextBeatFrame, now: now) }
            nextBeatFrame += step
            beatIndex += 1
        }
        if !player.isPlaying { player.play() }
    }

    private func scheduleDownbeatHaptic(at frame: AVAudioFramePosition, now: AVAudioFramePosition) {
        guard hapticsEnabled else { return }
        let token = runToken
        let delay = Double(frame - now) / format.sampleRate
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, self.runToken == token else { return }
                Haptics.downbeat()
            }
        }
    }

    private func currentFrame() -> AVAudioFramePosition {
        if let render = player.lastRenderTime,
           let time = player.playerTime(forNodeTime: render) {
            return time.sampleTime
        }
        if let render = engine.outputNode.lastRenderTime {
            return render.sampleTime
        }
        return 0
    }

    private func frames(_ seconds: Double) -> AVAudioFramePosition {
        AVAudioFramePosition(seconds * format.sampleRate)
    }

    private static func makeClick(
        format: AVAudioFormat, frequency: Double, amplitude: Double
    ) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * 0.03)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return buffer }
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            channel[i] = Float(sin(2 * .pi * frequency * t) * exp(-t * 90) * amplitude)
        }
        return buffer
    }

    deinit {
        pump?.invalidate()
        engine.stop()
    }
}
```

Do **not** call `engine.stop()` from `stop()`. Do **not** set `graphConfigured = false` on stop. `fill()` still requires `isPlaying`, so `start()` sets it true only after `engine.isRunning` is confirmed and `player.play()` has been called.

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MetronomeEngineTests test
```

Expected: `TEST SUCCEEDED`. `startStopStartRunsEngineWithoutSecondPump` uses the real session on Simulator; if it fails because `engine.isRunning` is false, fix `start()` (do not skip the test).

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/MetronomeEngine.swift foxgitaTests/MetronomeEngineTests.swift
git commit -m "fix: restart metronome engine after session release"
```

---

### Task 5: PracticeDetailView BPM and start coupling

**Files:**
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift` (`metronomeCard`, `togglePlay`)
- Modify: `foxgita/Localizable.xcstrings`

**Interfaces:**
- Consumes: `MetronomeEngine.start() throws`, `bump(_:)`
- Produces: ±1 buttons; accessibility 「降低 1 BPM」/「提高 1 BPM」; `togglePlay` starts the timer only after `start()` succeeds

- [ ] **Step 1: Change BPM controls and copy**

In `metronomeCard`, replace the two `circleBtn` actions and labels:

```swift
circleBtn("－", label: String(localized: "降低 1 BPM")) { metronome.bump(-1) }
```

```swift
circleBtn("＋", label: String(localized: "提高 1 BPM"), accent: true) {
    metronome.bump(1)
}
```

In `foxgita/Localizable.xcstrings`, rename the keys (keep empty objects, same catalog style):

- `"降低 5 BPM"` → `"降低 1 BPM"`
- `"提高 5 BPM"` → `"提高 1 BPM"`

Add:

```json
    "节拍器无法启动" : {

    },
```

Place it in alphabetical-ish order among existing Chinese keys (near other `节` entries if present; otherwise next to similar strings). Do not delete unrelated keys.

- [ ] **Step 2: Couple timer to metronome start**

Replace `togglePlay()` with:

```swift
    private func togglePlay() {
        if practiceTimer.isRunning {
            practiceTimer.pause()
            metronome.stop()
            return
        }
        do {
            try metronome.start()
            practiceTimer.start()
        } catch {
            show(String(localized: "节拍器无法启动"))
        }
    }
```

RESET, `onDisappear`, `requestExit`, `complete`, and interruption already call `metronome.stop()` — leave those. Interruption already pauses the timer; do not auto-start.

- [ ] **Step 3: Build the app target to confirm call site compiles**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MetronomeEngineTests test
```

Expected: compile succeeds (`start()` is now throwing; only `togglePlay` in this task should call it). `TEST SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add foxgita/Features/Practice/PracticeDetailView.swift foxgita/Localizable.xcstrings
git commit -m "fix: step metronome by 1 BPM and refuse timer on start failure"
```

---

### Task 6: Historical clips, timestamp, empty state, missing file

**Files:**
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift` (`openRecordings` / `visibleClips` / `clipList` / `clipCard` / `aiRow`)
- Modify: `foxgita/Localizable.xcstrings`

**Interfaces:**
- Consumes: `PracticeClipQuery.visible`, `PracticeClipQuery.timestamp`, `RecordingStore.fileExists(fileName:)`
- Produces: list of all undeleted recordings for the queried sessions; empty copy; 「文件缺失」; diagnosis/analysis present only if the file exists

- [ ] **Step 1: Point the list at PracticeClipQuery**

Delete `openRecordings`. Replace `visibleClips` with:

```swift
    private var visibleClips: [RecordingRef] {
        let descriptors = sessions.flatMap(\.recordings).map {
            PracticeClipDescriptor(
                id: $0.id, fileName: $0.fileName, createdAt: $0.createdAt, deletedAt: $0.deletedAt
            )
        }
        let visible = PracticeClipQuery.visible(
            clips: descriptors, videoMode: toolMode == .video
        )
        let byId = Dictionary(
            sessions.flatMap(\.recordings).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return visible.compactMap { byId[$0.id] }
    }
```

Keep `openSessionId` on persist / save / complete / `hasUnsavedWork`. Do not use it in `visibleClips`.

- [ ] **Step 2: Timestamp, missing badge, empty state, present guard**

Replace `relativeTime(rec.createdAt)` in `clipCard` with `PracticeClipQuery.timestamp(rec.createdAt)`.

Delete `relativeTime(_:)`.

In `clipCard`, after the subtitle (`姿势、指法…` / `节奏与和弦…`) and before `if configured { aiRow(rec) }`, add:

```swift
            if !RecordingStore.fileExists(fileName: rec.fileName) {
                Text(String(localized: "文件缺失"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitaTheme.statusError)
            }
```

Replace the 「查看诊断」 button action with:

```swift
                    Button(String(localized: "查看诊断")) {
                        presentIfFileExists(rec) {
                            diagnosisRoute = VideoRoute(id: rec.id, durationSec: rec.durationSec)
                        }
                    }
```

Add:

```swift
    private func presentIfFileExists(_ rec: RecordingRef, present: () -> Void) {
        guard RecordingStore.fileExists(fileName: rec.fileName) else {
            show(String(localized: "文件不存在或已被移除"))
            return
        }
        present()
    }
```

Leave `persist`'s `analysisRoute = VideoRoute(...)` as-is. That path already `guard`s the file on disk.

Replace `clipList` with:

```swift
    private func clipList(_ task: TaskItem) -> some View {
        VStack(spacing: 10) {
            if visibleClips.isEmpty {
                VStack(spacing: 8) {
                    Text(
                        toolMode == .video
                            ? String(localized: "还没有视频")
                            : String(localized: "还没有录音")
                    )
                    .font(.system(size: 14, weight: .semibold))
                    Text(
                        toolMode == .video
                            ? String(localized: "点上方「录视频」即可拍摄或从相册导入")
                            : String(localized: "点上方「录音」即可留下片段")
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(GitaTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(visibleClips, id: \.id) { rec in
                    clipCard(rec, taskTitle: task.title)
                }
            }
        }
    }
```

Add to `Localizable.xcstrings`:

```json
    "文件缺失" : {

    },
    "文件不存在或已被移除" : {

    },
    "还没有视频" : {

    },
    "点上方「录音」即可留下片段" : {

    },
    "点上方「录视频」即可拍摄或从相册导入" : {

    },
```

`还没有录音` already exists in the catalog (record detail). Do not duplicate it; reuse `String(localized: "还没有录音")`.

- [ ] **Step 3: Run clip query + store tests (no UI harness)**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeClipQueryTests \
  -only-testing:foxgitaTests/RecordingStoreTests \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

Expected: `TEST SUCCEEDED`. `PracticeStoreTests` still covers `beginOpenSession` / `appendRecording` write isolation.

- [ ] **Step 4: Commit**

```bash
git add foxgita/Features/Practice/PracticeDetailView.swift foxgita/Localizable.xcstrings
git commit -m "feat: show historical practice clips with missing-file state"
```

---

### Task 7: Record detail and playback guards

**Files:**
- Modify: `foxgita/Features/Record/RecordDetailView.swift` (play button ~197, diagnosis action ~296)
- Modify: `foxgita/Services/AudioRecorderService.swift` (`AudioPlayerService.toggle`)
- Modify: `foxgita/Features/Practice/VideoDiagnosisView.swift` (`DiagnosisClipPlayer.load`)

**Interfaces:**
- Consumes: `RecordingStore.fileExists(fileName:)`
- Produces: toast 「文件不存在或已被移除」 on play/diagnosis; players no-op on missing files

- [ ] **Step 1: Guard RecordDetailView**

Add:

```swift
    private func presentIfFileExists(_ rec: RecordingRef, present: () -> Void) {
        guard RecordingStore.fileExists(fileName: rec.fileName) else {
            show(String(localized: "文件不存在或已被移除"))
            return
        }
        present()
    }
```

Replace the play button action:

```swift
                            Button {
                                presentIfFileExists(r) {
                                    player.toggle(url: r.fileURL, id: r.id)
                                }
                            } label: {
```

Replace the 「查看诊断」 action:

```swift
            actionRow(String(localized: "查看诊断")) {
                presentIfFileExists(r) {
                    player.stop()
                    diagnosisId = r.id
                }
            }
```

- [ ] **Step 2: Defend AudioPlayerService and DiagnosisClipPlayer**

At the top of `AudioPlayerService.toggle(url:id:)` after the `playingId == id` early return / `stop()`:

```swift
        guard FileManager.default.fileExists(atPath: url.path) else {
            playingId = nil
            return
        }
```

At the top of `DiagnosisClipPlayer.load(url:)`:

```swift
        guard FileManager.default.fileExists(atPath: url.path) else { return }
```

Keep the existing `didAcquirePlayback` flag so `stop()` does not release a session that was never acquired.

- [ ] **Step 3: Compile via unit tests**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add foxgita/Features/Record/RecordDetailView.swift \
  foxgita/Services/AudioRecorderService.swift \
  foxgita/Features/Practice/VideoDiagnosisView.swift
git commit -m "fix: toast and no-op when a recording file is missing"
```

---

### Task 8: Docs and regression sweep

**Files:**
- Modify: `docs/TECHNICAL.md`
- Modify: `docs/TEST_PLAN_CLI.md`

**Interfaces:**
- Consumes: behavior from Tasks 1–7
- Produces: documented restart rule + new test suites in the CLI plan

- [ ] **Step 1: TECHNICAL.md**

In §5.2 MetronomeEngine, after the four numbered sampling bullets, add:

```markdown
暂停会 `player.stop()` 并 `release(.playback)`（可能 `setActive(false)`）。再次 `start()` 不得只看自维护标志；必须在 acquire 之后确认 `engine.isRunning`，否则 `try engine.start()`。Graph（attach / connect / click buffer）只建一次，stop 不 `engine.stop()`、不拆节点。`start()` 失败时 `isPlaying` 保持 false，并 release 本次 playback need。
```

In §5.4 RecordingStore row, mention `fileExists(fileName:)`.

In the 练习详情 description (wherever it says clips are the current session only), note: 列表展示该 `taskId` 下全部未删除 recording；`openSessionId` 只用于写入。

- [ ] **Step 2: TEST_PLAN_CLI.md**

Add suite rows under Step B:

| `PracticeClipQueryTests` | 已删过滤、音视频分类、`createdAt` 倒序、id 去重、`8月16日 14:32` |
| `RecordingStoreTests` | 写入后 `fileExists` true，删除后 false |
| `AudioSessionCoordinatorTests` | apply 失败回滚计数；成对 acquire/release；record+playback 仍 prefersPlayAndRecord |
| `MetronomeEngineTests` | `bump(1)` 钳制；acquire 失败 `isPlaying == false`；start/stop/start 引擎 running 且无第二份 pump |

- [ ] **Step 3: Run full unit tests**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: `TEST SUCCEEDED`.

If time allows, also:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

Expected: unit + UI smoke `TEST SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add docs/TECHNICAL.md docs/TEST_PLAN_CLI.md
git commit -m "docs: record metronome restart and historical clip tests"
```

---

## Device DoD (not a coding task)

After Task 8, on a physical iPhone:

1. Speaker: start → pause 2s → start, ten times; sound within 300 ms; timer continues.
2. Pause, set BPM 83, start; clicks at 83.
3. Record audio while metronome runs; recording is not killed.
4. One wired or Bluetooth route.
5. Foreground/background; phone-call / alarm interruption leaves a stopped metronome; manual start works.
6. Save audio, live video, album video; leave; re-enter the same task; lists show them with `M月d日 HH:mm`.
7. Task A vs B do not mix clips.
8. Delete a sandbox file; card shows 「文件缺失」; diagnosis/play toasts 「文件不存在或已被移除」.

---

## Self-review

| Spec section | Task |
|---|---|
| BPM ±1, clamp, a11y | 4 (engine) + 5 (view/copy) |
| start/stop graph split, throw, no `engineStarted`-only fix | 4 |
| Timer stays stopped on start failure | 5 |
| acquire rollback, playAndRecord | 3 |
| Debug logs | 4 |
| PracticeClipQuery flatten/filter/sort/dedupe | 1 + 6 |
| Absolute timestamp | 1 + 6 |
| Empty states | 6 |
| Missing badge + toast, no in-practice play | 6 + 7 |
| `openSessionId` write isolation | 6 (unchanged persist) + existing PracticeStoreTests |
| Record detail / player guards | 7 |
| TECHNICAL / TEST_PLAN | 8 |
| P1/P2 / schema / in-practice play | explicitly omitted |
