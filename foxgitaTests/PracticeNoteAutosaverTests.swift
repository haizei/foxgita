import Foundation
import Testing
@testable import foxgita

@MainActor
struct PracticeNoteAutosaverTests {
    enum Failure: Error { case diskFull }

    @Test func flushSavesLatestDraftAndFailureCanRetry() throws {
        var written: [String] = []
        var fail = true
        let saver = PracticeNoteAutosaver(initialText: "原笔记", delay: .seconds(60)) { text in
            if fail { throw Failure.diskFull }
            written.append(text)
        }
        saver.schedule("修改一")
        saver.schedule("最终修改")
        #expect(throws: Failure.self) { try saver.flush() }
        #expect(saver.savedText == "原笔记")
        #expect(written.isEmpty)
        fail = false
        try saver.flush()
        #expect(written == ["最终修改"])
        #expect(saver.savedText == "最终修改")
        #expect(saver.state == .saved)
        try saver.flush()
        #expect(written.count == 1)
    }
}
