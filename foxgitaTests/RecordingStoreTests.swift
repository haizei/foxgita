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
