import Foundation
import Observation

@Observable @MainActor final class OriginalScoreRuntime {
    private(set) var run: OriginalScoreRun
    private(set) var metronome: Bool
    private(set) var message: String?
    private(set) var saveFailed = false
    let library: OriginalScoreLibrary
    private let store: PracticeStore
    private let settings: OriginalScoreSettings
    private let preferred: UUID?
    private let completed: Set<UUID>
    private let audio = OriginalScoreAudio()
    private var task: Task<Void, Never>?
    private var observer: UUID?
    private var lastClock = 0.0
    private var preparingClock = 0.0
    private var savedElapsed = 0.0
    private var pending: [ScoreDaySlice] = []
    private var allocations: [String: Double] = [:]
    private var bases: [String: Int] = [:]
    private var items: [String: PracticeItem] = [:]
    private var checkpointIDs: [String: UUID] = [:]
    private var recordIDs: [String: UUID] = [:]
    private var recordSeconds: [String: Double] = [:]
    private var recordDates: [String: Date] = [:]
    private let runID = UUID()

    init(document: OriginalScoreDocument, library: OriginalScoreLibrary, store: PracticeStore,
         entry: ScoreHubEntry, settings: OriginalScoreSettings, completed: Set<UUID>, resumeAtRowStart: Bool = true) throws {
        self.library = library; self.store = store; self.settings = settings; self.completed = completed
        if case .existing(let id) = entry { preferred = id } else { preferred = nil }
        let progress = library.progress(for: document.versionID)
        do { run = try .init(document: document, progress: progress, resumeAtRowStart: resumeAtRowStart) }
        catch {
            run = try .init(document: document)
            message = "恢复位置已失效，已回到全部谱行起点。"
        }
        metronome = progress?.metronome ?? settings.enabled
        // Replay the durable journal before taking a new cumulative baseline.
        for checkpoint in library.pendingCheckpoints {
            try store.commitScoreElapsed(itemID: checkpoint.practiceItemID, expectedDayKey: checkpoint.dayKey,
                                         absoluteSeconds: checkpoint.absoluteSeconds, now: Date())
            try library.markCommitted(checkpoint.id)
        }
        observer = AudioSessionCoordinator.shared.addInterruptionObserver { [weak self] _ in
            self?.pause(); self?.message = "播放已暂停，请手动继续。"
        }
    }

    func play(preparing: Bool = false) {
        guard run.state != .playing, run.state != .preparing else { return }
        if observer == nil {
            observer = AudioSessionCoordinator.shared.addInterruptionObserver { [weak self] _ in
                self?.pause(); self?.message = "播放已暂停，请手动继续。"
            }
        }
        persist()
        guard !saveFailed else { return }
        if preparing {
            run.prepare(); preparingClock = ProcessInfo.processInfo.systemUptime
        } else {
            run.play()
            do { try startAudio() } catch { fail(error); return }
        }
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, let self else { return }
                self.tick()
                if self.run.state != .playing && self.run.state != .preparing { return }
            }
        }
    }

    private func startAudio() throws {
        try audio.start(run: run, settings: settings, enabled: metronome)
        lastClock = 0
    }

    func tick() {
        let previous = run.elapsedSeconds
        if run.state == .preparing {
            let now = ProcessInfo.processInfo.systemUptime
            run.advance(seconds: max(0, now - preparingClock)); preparingClock = now
            if run.state == .playing {
                do { try startAudio() } catch { fail(error) }
            }
        } else if run.state == .playing {
            let now = audio.seconds
            run.advance(seconds: max(0, now - lastClock)); lastClock = now
            audio.schedule()
        }
        let delta = run.elapsedSeconds - previous
        if delta > 0 { pending += ScoreDayPartition.split(endingAt: Date(), seconds: delta, calendar: .current) }
        if run.state == .completed { audio.stop(); persist() }
        else if run.elapsedSeconds - savedElapsed >= 5 { persist() }
    }

    func pause() {
        if run.state == .playing || run.state == .preparing { tick() }
        if run.state != .completed { run.pause() }
        task?.cancel(); task = nil; audio.stop()
        persist()
    }

    func setMetronome(_ value: Bool) { metronome = value; audio.mute(!value); persist() }
    func setBPM(_ value: Double) {
        pause(); guard !saveFailed else { return }
        do { try run.setBPM(value); newRecordSegment(); persist() } catch { fail(error) }
    }
    func setRange(_ value: OriginalScoreRange) {
        pause(); guard !saveFailed else { return }
        do { try run.setRange(value); newRecordSegment(); persist() } catch { fail(error) }
    }
    func setLooping(_ value: Bool) { pause(); guard !saveFailed else { return }; run.setLooping(value); persist() }
    func rewind() { pause(); guard !saveFailed else { return }; run.rewind(); persist() }
    private func newRecordSegment() { recordIDs = [:]; recordSeconds = [:]; recordDates = [:] }

    func persist() {
        do {
            while let slice = pending.first {
                if items[slice.dayKey] == nil {
                    let item = try store.openOriginalScorePractice(document: run.document, bpm: run.bpm,
                        preferred: preferred, completed: completed, now: slice.date, calendar: .current)
                    items[slice.dayKey] = item; bases[slice.dayKey] = item.durationSeconds
                }
                allocations[slice.dayKey, default: 0] += slice.seconds
                recordSeconds[slice.dayKey, default: 0] += slice.seconds
                if recordDates[slice.dayKey] == nil { recordDates[slice.dayKey] = slice.date }
                pending.removeFirst()
            }
            for (day, seconds) in allocations {
                guard let item = items[day] else { continue }
                let checkpointID = checkpointIDs[day] ?? UUID(); checkpointIDs[day] = checkpointID
                let checkpoint = ScoreSaveCheckpoint(id: checkpointID, runID: runID, practiceItemID: item.id,
                    dayKey: day, absoluteSeconds: (bases[day] ?? 0) + Int(seconds), runSeconds: Int(seconds))
                let recordID = recordIDs[day] ?? UUID(); recordIDs[day] = recordID
                let amount = recordSeconds[day, default: 0]
                if amount > 0 {
                    try library.save(checkpoint: checkpoint, record: .init(id: recordID, practiceItemID: item.id,
                        versionID: run.document.versionID, range: run.range, bpm: run.bpm, seconds: amount,
                        date: recordDates[day] ?? item.createdAt))
                    try store.commitScoreElapsed(itemID: item.id, expectedDayKey: day,
                                                 absoluteSeconds: checkpoint.absoluteSeconds, now: Date())
                    try library.markCommitted(checkpoint.id)
                }
            }
            try library.save(progress: run.progress(metronome: metronome))
            savedElapsed = run.elapsedSeconds; saveFailed = false
        } catch { saveFailed = true; fail(error) }
    }

    private func fail(_ error: Error) {
        run.pause(); audio.stop(); task?.cancel(); task = nil
        message = error.localizedDescription
    }
    func close() {
        pause()
        if !saveFailed {
            if let observer { AudioSessionCoordinator.shared.removeInterruptionObserver(observer) }
            observer = nil
        }
    }
}
