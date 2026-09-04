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
        recordingCount: Int = 0,
        startedAt: Date? = nil
    ) -> ResumeSession {
        ResumeSession(
            id: id,
            endedAt: endedAt,
            bpm: bpm,
            noteText: note,
            deletedAt: deletedAt,
            durationSec: durationSec,
            recordingCount: recordingCount,
            startedAt: startedAt ?? endedAt.addingTimeInterval(TimeInterval(-durationSec))
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

    @Test func continuableUsesLatestEffective() {
        let state = PracticeResumeQuery.resume(
            sessions: [
                session(id: "old", endedAt: t0, bpm: 70, note: "旧", durationSec: 30),
                session(id: "new", endedAt: t2, bpm: 88, note: "新笔记", durationSec: 120),
            ],
            recordings: [],
            defaultBpm: 80
        )
        #expect(state.openSessionId == "new")
        #expect(state.durationSec == 120)
        #expect(state.noteText == "新笔记")
        #expect(state.bpm == 88)
    }

    @Test func skippedLatestIsNotContinuable() {
        let state = PracticeResumeQuery.resume(
            sessions: [
                session(id: "sealed", endedAt: t2, bpm: 90, note: "封", durationSec: 50),
                session(id: "older", endedAt: t0, bpm: 70, note: "更早", durationSec: 20),
            ],
            recordings: [],
            defaultBpm: 80,
            skippedSessionId: "sealed"
        )
        #expect(state.openSessionId == nil)
        #expect(state.durationSec == 0)
        #expect(state.noteText == "")
        #expect(state.hasHistory)
        #expect(state.bpm == 90)
    }

    @Test func skippedWithNoOtherHistoryStillHidesContinuable() {
        let state = PracticeResumeQuery.resume(
            sessions: [session(id: "only", endedAt: t1, bpm: 66, note: "x", durationSec: 10)],
            recordings: [],
            defaultBpm: 80,
            skippedSessionId: "only"
        )
        #expect(state.openSessionId == nil)
        #expect(state.durationSec == 0)
        #expect(state.hasHistory)
    }

    @Test func newItemHidesFocusWhenNoLineage() {
        let current = lineage(id: UUID(), originId: "template.chord", title: "和弦转换")
        let state = PracticeItemResumeQuery.resume(
            current: current,
            items: [current],
            recordings: [],
            defaultBpm: 80
        )
        #expect(state.bpm == 80)
        #expect(!state.hasHistory)
        #expect(PracticeResumeQuery.focusLine(state: state) == nil)
    }

    @Test func sameOriginYesterdaySeedsBpmAndFocus() {
        let currentId = UUID()
        let yesterdayId = UUID()
        let current = lineage(
            id: currentId,
            originId: "template.chord",
            title: "和弦转换",
            createdAt: t2
        )
        let yesterday = lineage(
            id: yesterdayId,
            originId: "template.chord",
            title: "和弦转换",
            bpm: 63,
            note: "食指闷音",
            durationSeconds: 120,
            createdAt: t0
        )
        let state = PracticeItemResumeQuery.resume(
            current: current,
            items: [current, yesterday],
            recordings: [],
            defaultBpm: 80
        )
        #expect(state.bpm == 63)
        #expect(state.hasHistory)
        #expect(PracticeResumeQuery.focusLine(state: state) == "上次 63 BPM · 食指闷音")
        #expect(
            PracticeItemResumeQuery.seedBpm(
                originId: "template.chord",
                title: "和弦转换",
                sourceRaw: PracticeItemSource.recommend.rawValue,
                items: [yesterday],
                fallback: 80
            ) == 63
        )
    }

    @Test func titleAndSourceMatchWhenOriginIsUniquePerGeneration() {
        let current = lineage(
            id: UUID(),
            originId: "ai.photo.today",
            title: "扫弦入门",
            sourceRaw: PracticeItemSource.photo.rawValue,
            createdAt: t2
        )
        let previous = lineage(
            id: UUID(),
            originId: "ai.photo.yesterday",
            title: "扫弦入门",
            sourceRaw: PracticeItemSource.photo.rawValue,
            bpm: 72,
            durationSeconds: 90,
            createdAt: t0
        )
        let state = PracticeItemResumeQuery.resume(
            current: current,
            items: [current, previous],
            recordings: [],
            defaultBpm: 80
        )
        #expect(state.bpm == 72)
        #expect(PracticeResumeQuery.focusLine(state: state) == "上次练到 72 BPM")
    }

    @Test func currentEffectiveVisitBeatsYesterdayForFocus() {
        let current = lineage(
            id: UUID(),
            originId: "template.chord",
            title: "和弦转换",
            bpm: 70,
            note: "今天稳住了",
            durationSeconds: 60,
            createdAt: t2
        )
        let yesterday = lineage(
            id: UUID(),
            originId: "template.chord",
            title: "和弦转换",
            bpm: 50,
            note: "昨天",
            durationSeconds: 80,
            createdAt: t0
        )
        let state = PracticeItemResumeQuery.resume(
            current: current,
            items: [current, yesterday],
            recordings: [
                ResumeRecording(
                    id: "r1",
                    createdAt: t2,
                    deletedAt: nil,
                    reviewNextAction: "下次慢半拍"
                )
            ],
            defaultBpm: 80
        )
        #expect(state.bpm == 70)
        #expect(PracticeResumeQuery.focusLine(state: state) == "上次 70 BPM · 下次慢半拍")
    }

    @Test func ignoresDeletedAndEmptySiblings() {
        let current = lineage(id: UUID(), originId: "template.chord", title: "和弦转换")
        let empty = lineage(
            id: UUID(),
            originId: "template.chord",
            title: "和弦转换",
            bpm: 99,
            durationSeconds: 0,
            createdAt: t2
        )
        let gone = lineage(
            id: UUID(),
            originId: "template.chord",
            title: "和弦转换",
            bpm: 40,
            durationSeconds: 60,
            createdAt: t1,
            deletedAt: t1
        )
        let keep = lineage(
            id: UUID(),
            originId: "template.chord",
            title: "和弦转换",
            bpm: 55,
            durationSeconds: 30,
            createdAt: t0
        )
        let state = PracticeItemResumeQuery.resume(
            current: current,
            items: [current, empty, gone, keep],
            recordings: [],
            defaultBpm: 80
        )
        #expect(state.bpm == 55)
    }

    private func lineage(
        id: UUID,
        originId: String?,
        title: String,
        sourceRaw: String = PracticeItemSource.recommend.rawValue,
        bpm: Int? = nil,
        note: String = "",
        durationSeconds: Int = 0,
        createdAt: Date? = nil,
        deletedAt: Date? = nil
    ) -> PracticeLineageItem {
        PracticeLineageItem(
            id: id,
            originId: originId,
            title: title,
            sourceRaw: sourceRaw,
            bpm: bpm,
            note: note,
            durationSeconds: durationSeconds,
            recordingCount: durationSeconds > 0 ? 0 : 0,
            createdAt: createdAt ?? t1,
            deletedAt: deletedAt
        )
    }
}
