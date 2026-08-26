import Foundation
import Testing
@testable import foxgita

@MainActor
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

    @Test func referencedFileNamesIncludePracticeItemAndSessionRecordings() throws {
        let itemName = "item-\(UUID().uuidString).m4a"
        let sessionName = "session-\(UUID().uuidString).m4a"
        let item = PracticeItem(
            id: UUID(),
            profileId: UUID(),
            practiceDayKey: "2026-08-26",
            title: "开放弦",
            categoryRaw: PracticeCategory.left.rawValue,
            durationSeconds: 0
        )
        item.recordings.append(RecordingRef(id: "item-clip", fileName: itemName, bytes: 1))
        let session = PracticeSession(
            taskId: "warm",
            taskTitle: "指尖热身",
            category: .left,
            startedAt: Date(),
            endedAt: Date(),
            durationSec: 60,
            bpm: 80,
            timeSig: "4/4",
            steps: []
        )
        session.recordings.append(RecordingRef(id: "session-clip", fileName: sessionName, bytes: 1))

        let referenced = RecordingStore.referencedFileNames(
            practiceItems: [item],
            sessions: [session]
        )
        #expect(referenced.contains(itemName))
        #expect(referenced.contains(sessionName))
        #expect(referenced.count == 2)
    }

    @Test func removeOrphansKeepsPracticeItemAndSessionClips() throws {
        let itemName = "item-\(UUID().uuidString).m4a"
        let sessionName = "session-\(UUID().uuidString).m4a"
        let orphanName = "orphan-\(UUID().uuidString).m4a"
        try Data([0x01]).write(to: RecordingStore.url(for: itemName))
        try Data([0x01]).write(to: RecordingStore.url(for: sessionName))
        try Data([0x01]).write(to: RecordingStore.url(for: orphanName))
        defer {
            RecordingStore.delete(fileName: itemName)
            RecordingStore.delete(fileName: sessionName)
            RecordingStore.delete(fileName: orphanName)
        }

        let item = PracticeItem(
            id: UUID(),
            profileId: UUID(),
            practiceDayKey: "2026-08-26",
            title: "开放弦",
            categoryRaw: PracticeCategory.left.rawValue,
            durationSeconds: 0
        )
        item.recordings.append(RecordingRef(id: "item-clip", fileName: itemName, bytes: 1))
        let session = PracticeSession(
            taskId: "warm",
            taskTitle: "指尖热身",
            category: .left,
            startedAt: Date(),
            endedAt: Date(),
            durationSec: 60,
            bpm: 80,
            timeSig: "4/4",
            steps: []
        )
        session.recordings.append(RecordingRef(id: "session-clip", fileName: sessionName, bytes: 1))

        let referenced = RecordingStore.referencedFileNames(
            practiceItems: [item],
            sessions: [session]
        )
        let removed = RecordingStore.removeOrphans(referenced: referenced)
        #expect(removed >= 1)
        #expect(RecordingStore.fileExists(fileName: itemName))
        #expect(RecordingStore.fileExists(fileName: sessionName))
        #expect(!RecordingStore.fileExists(fileName: orphanName))
    }
}
