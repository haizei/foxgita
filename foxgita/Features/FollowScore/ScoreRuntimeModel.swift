import AVFoundation
import Foundation
import Observation

@Observable @MainActor final class ScoreRuntimeModel {
    private(set) var run: ScoreRun
    private(set) var item: PracticeItem
    let library: ScoreLibrary
    let visualClock: ScoreVisualClock
    var notation: ScoreNotation = .tablature
    var showLyrics = true
    var showChords = true
    var message: String?
    var listening = false
    private(set) var lastSaveSucceeded = true
    var isStarting = false
    private(set) var feedback = "准备好后开始跟练"
    private(set) var grade = ScoreGradeSummary(judgedEvents: 0,expectedEvents: 0,pitchAccuracy: nil,rhythmAccuracy: nil,totalScore: nil)
    var demoVolume = 0.7 { didSet { audio.demoVolume = demoVolume } }
    var clickVolume = 0.5 { didSet { audio.clickVolume = clickVolume } }

    @ObservationIgnored private let store: PracticeStore
    @ObservationIgnored private let passageID: UUID?
    @ObservationIgnored private let audio: any ScoreAudioDriving
    @ObservationIgnored private var grader: ScorePerformanceGrader
    @ObservationIgnored private var pollTask: Task<Void,Never>?
    @ObservationIgnored private var observer: UUID?
    @ObservationIgnored private var lastAudioSeconds = 0.0
    @ObservationIgnored private var segmentGradingOffset = 0.0
    @ObservationIgnored private var attemptID = UUID()
    @ObservationIgnored private var attemptStartElapsed = 0.0
    @ObservationIgnored private var savedAt = 0.0
    @ObservationIgnored private var allocations: [String:Double] = [:]
    @ObservationIgnored private var bases: [String:Int] = [:]
    @ObservationIgnored private var items: [String:PracticeItem] = [:]
    @ObservationIgnored private var checkpointIDs: [String:UUID] = [:]
    @ObservationIgnored private var pendingSlices: [ScoreDaySlice] = []
    @ObservationIgnored private var startGeneration = UUID()
    private struct SavedProgress: Equatable {
        var elapsed: Double; var tick: Int; var range: ScoreRange; var speed: Double
        var loops: Int?; var mode: ScoreRunMode; var notation: ScoreNotation
    }
    @ObservationIgnored private var lastSavedProgress: SavedProgress?
    @ObservationIgnored private var savedResultAttempt: UUID?
    @ObservationIgnored private var savedResultElapsed: Double?

    init(score: ScoreDocument,item: PracticeItem,library: ScoreLibrary,store: PracticeStore,range: ScoreRange,speed: Double,loops: Int? = nil,mode: ScoreRunMode = .practice,passageID: UUID? = nil,resumeTick: Int? = nil,audio: (any ScoreAudioDriving)? = nil) throws {
        var initialRun = try ScoreRun(score: score,range: range,speed: speed,loopLimit: loops,mode: mode)
        if let resumeTick { try initialRun.seek(toBar: max(range.firstBar,min(range.lastBar,score.barIndex(atTick: resumeTick)))) }
        run = initialRun
        visualClock = ScoreVisualClock(run: initialRun)
        self.item = item; self.library = library; self.store = store; self.passageID = passageID
        self.audio = audio ?? ScoreAudioEngine()
        grader = ScorePerformanceGrader(score: score,range: range,speed: initialRun.speed,loopLimit: initialRun.remainingTraversals)
        grader.begin(at: gradingPosition)
        items[item.practiceDayKey] = item; bases[item.practiceDayKey] = item.durationSeconds
        for pending in library.checkpoints where !pending.committed {
            try store.commitScoreElapsed(itemID: pending.practiceItemID,expectedDayKey: pending.dayKey,absoluteSeconds: pending.absoluteSeconds,now: Date())
            try library.markCommitted(pending.id)
        }
        bases[item.practiceDayKey] = item.durationSeconds
        observer = AudioSessionCoordinator.shared.addInterruptionObserver { [weak self] _ in self?.pause(reason: "播放已暂停，请手动继续") }
    }

    func start() async {
        guard !isStarting, run.state != .playing, run.state != .countingIn else { return }
        let restarting = run.state == .finished
        if restarting { persist(result: true); guard lastSaveSucceeded else { return } }
        isStarting = true
        let token = UUID(); startGeneration = token
        run.start()
        if restarting { resetAttempt() }
        do {
            audio.demoVolume = demoVolume; audio.clickVolume = clickVolume
            segmentGradingOffset = gradingPosition
            audio.onObservation = { [weak self] observation,time in
                guard let self, self.run.state == .playing, time >= 0 else { return }
                self.grader.observe(observation,at: self.segmentGradingOffset+time)
                self.grade = self.grader.summary; self.feedback = self.grader.feedback
            }
            try await audio.start(run: run)
            guard startGeneration == token else { return }
            guard !Task.isCancelled else { audio.stop(); run.pause(); isStarting = false; return }
            listening = audio.listening
            feedback = listening ? "跟着节拍弹奏" : (audio.listeningUnavailableReason ?? "麦克风未开启，仍可无评分跟谱")
            lastAudioSeconds = 0
            visualClock.synchronize(run)
            pollTask?.cancel()
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let self else { return }
                    self.tick()
                }
            }
        } catch {
            guard startGeneration == token else { return }
            run.pause(); message = error.localizedDescription
        }
        if startGeneration == token { isStarting = false }
    }

    func tick() {
        if listening && !audio.listening { listening = false; feedback = audio.listeningUnavailableReason ?? "收音已暂停，继续无评分跟谱" }
        let rendered = audio.seconds
        let previous = run.elapsedSeconds
        run.advance(by: max(0,rendered-lastAudioSeconds)); lastAudioSeconds = rendered
        visualClock.synchronize(run)
        let delta = run.elapsedSeconds-previous
        if delta > 0 { allocate(delta: delta,now: Date()) }
        if run.elapsedSeconds-savedAt >= 5 { persist() }
        if run.state == .finished { pause(reason: "本轮练习已结束"); grader.finish(at: gradingPosition); grade = grader.summary; persist(result: true) }
    }
    private var gradingPosition: Double { Double(run.playbackLoops)*run.rangeDuration+run.positionSeconds }
    private func allocate(delta: Double,now: Date) {
        pendingSlices += ScoreDayPartition.split(endingAt: now,seconds: delta,calendar: .current)
        do {
            try drainAllocations()
        } catch {
            run.pause(); audio.stop(); pollTask?.cancel(); pollTask = nil; listening = false
            visualClock.synchronize(run)
            message = "记录保存失败，请重试：\(error.localizedDescription)"
        }
    }
    private func drainAllocations() throws {
            while let slice = pendingSlices.first {
                if items[slice.dayKey] == nil {
                    let next = try store.openScorePractice(score: run.score,preferredItemID: nil,completedIDs: [],now: slice.date,calendar: .current,origin: "\(run.id.uuidString):\(slice.dayKey)")
                    items[slice.dayKey] = next; bases[slice.dayKey] = next.durationSeconds
                }
                if let target = items[slice.dayKey] {
                    try library.save(link: .init(practiceItemID: target.id,versionID: run.score.versionID,range: run.range,speed: run.speed))
                }
                allocations[slice.dayKey,default: 0] += slice.seconds
                if let next = items[slice.dayKey] { item = next }
                pendingSlices.removeFirst()
            }
    }

    func pause(reason: String? = nil) {
        startGeneration = UUID()
        if run.state == .playing || run.state == .countingIn {
            let before = run.elapsedSeconds
            let rendered = audio.seconds
            run.advance(by: max(0,rendered-lastAudioSeconds)); lastAudioSeconds = rendered
            if run.elapsedSeconds > before { allocate(delta: run.elapsedSeconds-before,now: Date()) }
        }
        run.pause(); audio.stop(); listening = false
        visualClock.synchronize(run)
        pollTask?.cancel(); pollTask = nil; isStarting = false
        if let reason { feedback = reason }
        persist()
    }
    func persist(result: Bool = false) {
        let progress = SavedProgress(elapsed: run.elapsedSeconds,tick: run.tick,range: run.range,speed: run.speed,
            loops: run.loopLimit,mode: run.mode,notation: notation)
        let needsResult = result && run.elapsedSeconds > attemptStartElapsed
            && (savedResultAttempt != attemptID || savedResultElapsed != run.elapsedSeconds)
        let needsProgress = !lastSaveSucceeded || progress != lastSavedProgress || !pendingSlices.isEmpty
        guard needsProgress || needsResult else { return }
        do {
            try drainAllocations()
            if needsProgress {
              for (day,seconds) in allocations {
                guard let item = items[day] else { continue }
                let id = checkpointIDs[day] ?? UUID(); checkpointIDs[day] = id
                let checkpoint = ScoreSaveCheckpoint(id: id,runID: run.id,practiceItemID: item.id,dayKey: day,
                    absoluteSeconds: (bases[day] ?? 0)+Int(seconds),runSeconds: Int(seconds))
                try library.save(checkpoint: checkpoint)
                try store.commitScoreElapsed(itemID: item.id,expectedDayKey: day,absoluteSeconds: checkpoint.absoluteSeconds,now: Date())
                try library.markCommitted(id)
              }
              let bar = max(run.range.firstBar,min(run.range.lastBar,run.timeline.barIndex(atTick: run.tick)))
              try library.save(resume: .init(versionID: run.score.versionID,tick: run.timeline.startTick(ofBar: bar),speed: run.speed,range: run.range,notation: notation))
            }
            if needsResult {
                grader.finish(at: gradingPosition); grade = grader.summary
                try library.save(result: .init(id: attemptID,practiceItemID: item.id,versionID: run.score.versionID,passageID: passageID,
                    range: run.range,speed: run.speed,mode: run.mode,seconds: Int(run.elapsedSeconds-attemptStartElapsed),completedLoops: run.completedLoops,
                    judgedEvents: grade.judgedEvents,expectedEvents: grade.expectedEvents,pitchAccuracy: grade.pitchAccuracy,
                    rhythmAccuracy: grade.rhythmAccuracy,totalScore: grade.totalScore,completePerformance: run.isCompletePerformance))
                savedResultAttempt = attemptID; savedResultElapsed = run.elapsedSeconds
            }
            savedAt = run.elapsedSeconds
            lastSavedProgress = progress
            lastSaveSucceeded = true
        } catch { lastSaveSucceeded = false; message = "保存失败：\(error.localizedDescription)" }
    }
    func configure(range: ScoreRange,speed: Double,loops: Int?) {
        pause()
        persist(result: true)
        guard lastSaveSucceeded else { return }
        do {
            try run.configure(range: range,speed: speed,loopLimit: loops)
            visualClock.synchronize(run)
            grader = .init(score: run.score,range: range,speed: run.speed,loopLimit: run.remainingTraversals)
            attemptID = UUID(); attemptStartElapsed = run.elapsedSeconds
            grade = grader.summary
            try library.save(link: .init(practiceItemID: item.id,versionID: run.score.versionID,range: range,speed: run.speed))
            persist()
        } catch { message = error.localizedDescription }
    }
    private func resetAttempt() {
        attemptID = UUID(); attemptStartElapsed = run.elapsedSeconds
        grader = .init(score: run.score,range: run.range,speed: run.speed,loopLimit: run.remainingTraversals)
        grader.begin(at: gradingPosition)
        grade = grader.summary
    }
    func changeMode(_ mode: ScoreRunMode) {
        pause(); persist(result: true); guard lastSaveSucceeded else { return }
        do { try run.changeMode(mode); visualClock.synchronize(run); resetAttempt(); persist() } catch { message = error.localizedDescription }
    }
    func rewind() { pause(); persist(result: true); guard lastSaveSucceeded else { return }; run.rewind(); visualClock.synchronize(run); resetAttempt(); persist() }
    func seek(toBar index: Int) {
        pause(); persist(result: true); guard lastSaveSucceeded else { return }
        do { try run.seek(toBar: index); visualClock.synchronize(run); resetAttempt(); persist() } catch { message = error.localizedDescription }
    }
    func close() {
        pause(); persist(result: true)
        if lastSaveSucceeded {
            if let observer { AudioSessionCoordinator.shared.removeInterruptionObserver(observer) }
            observer = nil
        }
    }
}
