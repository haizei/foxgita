import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

@MainActor struct OriginalScoreLibraryTests {
    @Test func durableCheckpointAlwaysRetainsItsHistoricalMaterialBeforeExternalCommit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = UUID()
        let library = try OriginalScoreLibrary(directory: directory, profileID: profile)
        let row = OriginalScoreRow(page: 0, box: .init(x: 0, y: 0, width: 1, height: 0.2), beats: 4)
        let draft = OriginalScoreDraft(document: .init(title: "日志", pageCount: 1, rows: [row]))
        try library.save(draft: draft)
        let document = try library.publish(draftID: draft.id, availablePages: 1)
        let item = UUID()
        let record = OriginalScorePracticeRecord(id: UUID(), practiceItemID: item, versionID: document.versionID,
            range: document.fullRange!, bpm: 80, seconds: 7.5)
        let checkpoint = ScoreSaveCheckpoint(id: UUID(), runID: UUID(), practiceItemID: item,
            dayKey: "2026-11-07", absoluteSeconds: 27, runSeconds: 7)
        try library.save(checkpoint: checkpoint, record: record)
        let reopened = try OriginalScoreLibrary(directory: directory, profileID: profile)
        #expect(reopened.pendingCheckpoints == [checkpoint])
        #expect(reopened.records == [record])
        try reopened.markCommitted(checkpoint.id)
        #expect(reopened.pendingCheckpoints.isEmpty)
        #expect(reopened.records == [record])
    }
    @Test func geometryRevisionKeepsProgressButTimingRevisionResetsItWithoutRewritingHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = UUID()
        let library = try OriginalScoreLibrary(directory: directory, profileID: profile)
        let row = OriginalScoreRow(page: 0, box: .init(x: 0, y: 0, width: 1, height: 0.2), beats: 4)
        let draft = OriginalScoreDraft(document: .init(title: "修订", pageCount: 1, rows: [row]))
        try library.save(draft: draft)
        let original = try library.publish(draftID: draft.id, availablePages: 1)
        try library.save(progress: .init(versionID: original.versionID, rowID: row.id,
            rowBeat: 2.5, bpm: 72, range: original.fullRange!, looping: true))
        let record = OriginalScorePracticeRecord(id: UUID(), practiceItemID: UUID(), versionID: original.versionID,
            range: original.fullRange!, bpm: 72, seconds: 31)
        try library.save(record: record)
        var geometry = try library.beginRevision(original)
        geometry.document.rows[0].box.y = 0.4
        try library.save(draft: geometry)
        let second = try library.publish(draftID: geometry.id, availablePages: 1)
        #expect(library.progress(for: second.versionID)?.rowBeat == 2.5)
        var timing = try library.beginRevision(second)
        timing.document.rows[0].beats = 3.5
        try library.save(draft: timing)
        let third = try library.publish(draftID: timing.id, availablePages: 1)
        #expect(library.progress(for: third.versionID)?.rowBeat == 0)
        #expect(library.progress(for: third.versionID)?.looping == false)
        try library.hide(third.id)
        let reopened = try OriginalScoreLibrary(directory: directory, profileID: profile)
        #expect(reopened.documents.isEmpty)
        #expect(reopened.records == [record])
        #expect(reopened.version(original.versionID) == original)
    }

    @Test func profileIsolationAndConcurrentRevisionConflictPreserveDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try OriginalScoreLibrary(directory: directory, profileID: UUID())
        let row = OriginalScoreRow(page: 0, box: .init(x: 0, y: 0, width: 1, height: 0.2), beats: 4)
        let draft = OriginalScoreDraft(document: .init(title: "冲突", pageCount: 1, rows: [row]))
        try library.save(draft: draft)
        let original = try library.publish(draftID: draft.id, availablePages: 1)
        let first = try library.beginRevision(original)
        let stale = try library.beginRevision(original)
        _ = try library.publish(draftID: first.id, availablePages: 1)
        #expect(throws: OriginalScoreError.self) { try library.publish(draftID: stale.id, availablePages: 1) }
        #expect(library.drafts.contains { $0.id == stale.id })
        let other = try OriginalScoreLibrary(directory: directory, profileID: UUID())
        #expect(other.documents.isEmpty)
        #expect(other.drafts.isEmpty)
    }
    @Test func draftSurvivesReopenAndPublishingIsIdempotent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = UUID()
        let library = try OriginalScoreLibrary(directory: directory, profileID: profile)
        let row = OriginalScoreRow(page: 0, box: .init(x: 0, y: 0, width: 1, height: 0.2), beats: 4)
        let draft = OriginalScoreDraft(document: .init(title: "我的原谱", pageCount: 1, rows: [row]))
        try library.save(draft: draft)
        let reopened = try OriginalScoreLibrary(directory: directory, profileID: profile)
        #expect(reopened.drafts.first?.document == draft.document)
        let first = try reopened.publish(draftID: draft.id, availablePages: 1)
        let repeated = try reopened.publish(draftID: draft.id, availablePages: 1)
        #expect(first.versionID == repeated.versionID)
        #expect(reopened.documents.count == 1)
        #expect(reopened.drafts.isEmpty)
    }
}
