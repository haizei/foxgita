import Foundation
import Testing
@testable import foxgita

struct PracticeResumeQueryTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_100)
    private let t2 = Date(timeIntervalSince1970: 1_700_000_200)

    private func session(
        id: String,
        endedAt: Date,
        bpm: Int,
        note: String = "",
        deletedAt: Date? = nil,
        durationSec: Int = 60,
        recordingCount: Int = 0
    ) -> ResumeSession {
        ResumeSession(
            id: id, endedAt: endedAt, bpm: bpm, noteText: note,
            deletedAt: deletedAt, durationSec: durationSec, recordingCount: recordingCount
        )
    }

    @Test func noSessionUsesDefaultAndHidesLine() {
        let state = PracticeResumeQuery.resume(sessions: [], recordings: [], defaultBpm: 80)
        #expect(state == ResumeState(bpm: 80, focus: nil, hasHistory: false))
        #expect(PracticeResumeQuery.focusLine(state: state) == nil)
    }

    @Test func lastEffectiveBpmBeatsDefault() {
        let state = PracticeResumeQuery.resume(
            sessions: [session(id: "s", endedAt: t1, bpm: 63)],
            recordings: [],
            defaultBpm: 80
        )
        #expect(state.bpm == 63)
        #expect(state.hasHistory)
        #expect(PracticeResumeQuery.focusLine(state: state) == "上次练到 63 BPM")
    }

    @Test func skipsInvalidAndDeletedSessions() {
        let state = PracticeResumeQuery.resume(
            sessions: [
                session(id: "empty", endedAt: t2, bpm: 99, durationSec: 0, recordingCount: 0),
                session(id: "gone", endedAt: t2, bpm: 50, deletedAt: t2),
                session(id: "old", endedAt: t0, bpm: 70),
            ],
            recordings: [],
            defaultBpm: 80
        )
        #expect(state.bpm == 70)
    }

    @Test func nextActionBeatsNoteAndUsesNewestRecording() {
        let state = PracticeResumeQuery.resume(
            sessions: [session(id: "s", endedAt: t1, bpm: 60, note: "食指闷音")],
            recordings: [
                ResumeRecording(id: "a", createdAt: t0, deletedAt: nil, reviewNextAction: "旧建议"),
                ResumeRecording(id: "b", createdAt: t2, deletedAt: nil, reviewNextAction: "下次慢半拍"),
                ResumeRecording(id: "c", createdAt: t2, deletedAt: t2, reviewNextAction: "已删"),
            ],
            defaultBpm: 80
        )
        #expect(state.focus == "下次慢半拍")
        #expect(PracticeResumeQuery.focusLine(state: state) == "上次 60 BPM · 下次慢半拍")
    }

    @Test func noteFirstLineTruncatesAt28() {
        let long = String(repeating: "啊", count: 30)
        let state = PracticeResumeQuery.resume(
            sessions: [session(id: "s", endedAt: t1, bpm: 72, note: "第一行\n第二行")],
            recordings: [],
            defaultBpm: 80
        )
        #expect(state.focus == "第一行")

        let longState = PracticeResumeQuery.resume(
            sessions: [session(id: "s", endedAt: t1, bpm: 72, note: long)],
            recordings: [],
            defaultBpm: 80
        )
        #expect(longState.focus == String(repeating: "啊", count: 28) + "…")
    }

    @Test func clampsBpm() {
        #expect(
            PracticeResumeQuery.resume(
                sessions: [session(id: "s", endedAt: t1, bpm: 39)],
                recordings: [],
                defaultBpm: 80
            ).bpm == 40
        )
        #expect(
            PracticeResumeQuery.resume(
                sessions: [session(id: "s", endedAt: t1, bpm: 201)],
                recordings: [],
                defaultBpm: 80
            ).bpm == 200
        )
    }
}
