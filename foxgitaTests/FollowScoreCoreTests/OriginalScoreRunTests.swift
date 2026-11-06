import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct OriginalScoreRunTests {
    @Test func sameSessionRevisionRetainsExactPositionWhileCrossSessionRestartsRow() throws {
        let row = OriginalScoreRow(page: 0, box: .init(x: 0, y: 0, width: 1, height: 0.2), beats: 4)
        let score = OriginalScoreDocument(title: "行框修订", pageCount: 1, rows: [row])
        let progress = OriginalScoreProgress(versionID: score.versionID, rowID: row.id, rowBeat: 2.5,
            bpm: 80, range: score.fullRange!)
        let sameSession = try OriginalScoreRun(document: score, progress: progress, resumeAtRowStart: false)
        #expect(sameSession.rowBeat == 2.5)
        let nextSession = try OriginalScoreRun(document: score, progress: progress)
        #expect(nextSession.rowBeat == 0)
    }
    @Test func selectedRangeLoopsWithoutPreparingAndSpeedChangesKeepHalfBeatPosition() throws {
        let rows = (0..<3).map { index in
            OriginalScoreRow(page: 0, box: .init(x: 0, y: Double(index) * 0.2, width: 1, height: 0.1), beats: 4)
        }
        let score = OriginalScoreDocument(title: "片段", pageCount: 1, initialBPM: 60, rows: rows)
        var run = try OriginalScoreRun(document: score)
        try run.setRange(.init(first: rows[1].id, last: rows[2].id))
        run.setLooping(true); run.play(); run.advance(seconds: 8.5)
        #expect(run.state == .playing)
        #expect(run.row.id == rows[1].id)
        #expect(run.rowBeat == 0.5)
        #expect(run.elapsedSeconds == 8.5)
        try run.setBPM(120)
        #expect(run.state == .paused)
        #expect(run.rowBeat == 0.5)
        run.play(); run.advance(seconds: 0.5)
        #expect(run.rowBeat == 1.5)
        let restored = try OriginalScoreRun(document: score, progress: run.progress(metronome: false))
        #expect(restored.state == .idle)
        #expect(restored.row.id == rows[1].id)
        #expect(restored.rowBeat == 0)
        #expect(restored.looping)
        #expect(restored.bpm == 120)
    }

    @Test func allRowsFinishOnceAndPreparationOnlyConsumesThreeSeconds() throws {
        let row = OriginalScoreRow(page: 0, box: .init(x: 0, y: 0, width: 1, height: 0.1), beats: 1.5)
        var run = try OriginalScoreRun(document: .init(title: "半拍", pageCount: 1, initialBPM: 60, rows: [row]))
        run.prepare(); run.advance(seconds: 20)
        #expect(run.state == .completed)
        #expect(run.elapsedSeconds == 1.5)
        run.play()
        #expect(run.rowBeat == 0)
        #expect(run.state == .playing)
    }
    @Test func preparationIsOptionalAndNeverAddsPracticeTime() throws {
        let row = OriginalScoreRow(page: 0, box: .init(x: 0, y: 0, width: 1, height: 0.2), beats: 4)
        let score = OriginalScoreDocument(title: "准备", pageCount: 1, initialBPM: 60, rows: [row])
        var run = try OriginalScoreRun(document: score)
        #expect(run.state == .idle)
        run.prepare()
        run.advance(seconds: 2)
        #expect(run.preparationRemaining == 1)
        #expect(run.elapsedSeconds == 0)
        run.pause()
        run.advance(seconds: 20)
        #expect(run.state == .paused)
        #expect(run.elapsedSeconds == 0)
        run.play()
        run.advance(seconds: 1.5)
        #expect(run.rowBeat == 1.5)
        #expect(run.elapsedSeconds == 1.5)
    }
}
