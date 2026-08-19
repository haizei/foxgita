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
