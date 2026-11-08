import Foundation
import Testing
@testable import foxgita

@MainActor struct ScoreRuntimeTests {
    @Test func visualClockDoesNotJumpBackwardWhenAnAudioBufferHasNotAdvanced() throws {
        var run = try ScoreRun(score: ScoreExercises.melody,range: ScoreExercises.melody.fullRange,speed: 1)
        run.start(countIn: false)
        let clock = ScoreVisualClock(run: run,uptime: 100)
        clock.synchronize(run,at: 100)
        let displayed = clock.tick(at: 100.08)
        clock.synchronize(run,at: 100.1) // Same audio buffer, delivered on the next poll.
        #expect(clock.tick(at: 100.101) >= displayed)
        run.pause(); try run.seek(toBar: 0); clock.synchronize(run,at: 100.2)
        #expect(clock.tick(at: 100.2) == 0,"Explicit transport jumps must not be suppressed.")
        run.start(countIn: false); run.advance(by: run.rangeDuration-0.05)
        clock.synchronize(run,at: 200)
        let end = clock.tick(at: 200),wrapped = clock.tick(at: 200.1)
        #expect(wrapped < end,"A real loop wrap must still move to A.")
        clock.synchronize(run,at: 200.1)
        #expect(clock.tick(at: 200.101) == wrapped,"A late pre-wrap audio sample cannot jump back to the previous loop.")
    }
    @Test func persistenceFailureStopsTheVisualClockAlongWithAudio() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PracticeStore(repository: InMemoryPracticeRepository(),defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.prepare()
        let score = ScoreExercises.melody,library = try ScoreLibrary(directory: folder,profileID: store.scoreProfileID())
        let item = try store.openScorePractice(score: score,preferredItemID: nil,completedIDs: [],now: Date(),calendar: .current,origin: "storage-error")
        let audio = TestScoreAudio()
        let model = try ScoreRuntimeModel(score: score,item: item,library: library,store: store,range: score.fullRange,speed: 1,audio: audio)
        await model.start()
        try FileManager.default.removeItem(at: folder)
        try Data().write(to: folder) // Make subsequent atomic library writes fail.
        audio.seconds = 7; model.tick()
        #expect(model.run.state == .paused)
        #expect(!model.visualClock.isAnimating)
        #expect(!audio.running)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        model.persist()
        #expect(model.lastSaveSucceeded)
        #expect(item.durationSeconds == Int(model.run.elapsedSeconds),"Retry must preserve the elapsed time pending when storage failed.")
        let allCommitted = library.checkpoints.allSatisfy { $0.committed }
        #expect(allCommitted)
        model.close()
    }
    @Test func savingThenDisappearingDoesNotWriteTheSamePracticeAgain() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = InMemoryPracticeRepository()
        let store = PracticeStore(repository: repository,defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.prepare()
        let score = ScoreExercises.melody
        let profile = try store.scoreProfileID()
        let library = try ScoreLibrary(directory: folder,profileID: profile)
        let item = try store.openScorePractice(score: score,preferredItemID: nil,completedIDs: [],now: Date(),calendar: .current,origin: "close-once")
        let audio = TestScoreAudio()
        let model = try ScoreRuntimeModel(score: score,item: item,library: library,store: store,range: score.fullRange,speed: 1,audio: audio)
        await model.start(); audio.seconds = 7; model.tick(); model.pause(); model.close()
        let saves = repository.saveCount
        let url = folder.appendingPathComponent(profile.uuidString+".json")
        let data = try Data(contentsOf: url)
        model.close() // SwiftUI onDisappear after the explicit save action.
        #expect(repository.saveCount == saves)
        #expect(try Data(contentsOf: url) == data)
        #expect(library.results.count == 1)
    }
    @Test func replayAfterFinishingGradesTheNewAttemptFromItsBeginning() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PracticeStore(repository: InMemoryPracticeRepository(),defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.prepare()
        let score = ScoreDocument(title: "再练",tempo: .init(bpm: 120),bars: [.init(number: 1,events: [.init(tick: 0,duration: 960,tones: [.init(midi: 64)])])])
        let library = try ScoreLibrary(directory: folder,profileID: store.scoreProfileID())
        try library.save(score: score)
        let item = try store.openScorePractice(score: score,preferredItemID: nil,completedIDs: [],now: Date(),calendar: .current,origin: "restart")
        let audio = TestScoreAudio()
        let model = try ScoreRuntimeModel(score: score,item: item,library: library,store: store,range: score.fullRange,speed: 1,loops: 1,audio: audio)
        for _ in 0..<2 {
            await model.start()
            audio.seconds = 2; model.tick() // count-in only
            audio.onObservation?(.init(pitches: [64:1],rms: 0.2,onset: true,quality: .reliable),0)
            audio.seconds = 4; model.tick()
            #expect(model.run.state == .finished)
            #expect(model.grade.totalScore == 100)
        }
        model.close()
        #expect(library.results.count == 2)
        #expect(item.durationSeconds == 4)
    }
    @Test func lateCancelledPermissionRequestCannotPauseANewerStart() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PracticeStore(repository: InMemoryPracticeRepository(),defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.prepare()
        let library = try ScoreLibrary(directory: folder,profileID: store.scoreProfileID())
        let score = ScoreExercises.melody
        let item = try store.openScorePractice(score: score,preferredItemID: nil,completedIDs: [],now: Date(),calendar: .current,origin: "race")
        let audio = TestScoreAudio(); audio.delayFirst = true
        let model = try ScoreRuntimeModel(score: score,item: item,library: library,store: store,range: score.fullRange,speed: 1,audio: audio)
        let first = Task { await model.start() }
        while audio.first == nil { await Task.yield() }
        model.pause()
        await model.start()
        audio.first?.resume(throwing: CancellationError()); audio.first = nil
        await first.value
        #expect(model.run.state == .countingIn)
        #expect(audio.running)
        #expect(!model.isStarting)
        model.close()
    }
}

@MainActor private final class TestScoreAudio: ScoreAudioDriving {
    var seconds = 0.0
    var listening = true
    var onObservation: ((ScorePitchObservation,Double) -> Void)?
    var demoVolume = 0.7, clickVolume = 0.5
    var delayFirst = false, running = false
    var first: CheckedContinuation<Void,any Error>?
    func start(run: ScoreRun) async throws {
        seconds = 0
        if delayFirst { delayFirst = false; try await withCheckedThrowingContinuation { first = $0 } }
        running = true
    }
    func stop() { running = false }
}
