import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

@MainActor struct ScoreLibraryTests {
    @Test func passageAndResumeAreSeparateAndSurviveRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = UUID()
        let library = try ScoreLibrary(directory: directory, profileID: profile)
        let score = ScoreExercises.strumming
        let passage = ScorePassage(versionID: score.versionID, title: "换弦", range: .init(firstBar: 2, lastBar: 3), speed: 0.75, loops: 5, note: "提前准备")
        try library.save(passage: passage)
        try library.save(resume: .init(versionID: score.versionID, tick: 6_000, speed: 0.5, range: score.fullRange))
        let reopened = try ScoreLibrary(directory: directory, profileID: profile)
        #expect(reopened.passages.first?.id == passage.id)
        #expect(reopened.passages.first?.range == .init(firstBar: 2, lastBar: 3))
        #expect(reopened.resumes.first?.tick == 6_000)
        let other = try ScoreLibrary(directory: directory, profileID: UUID())
        #expect(other.passages.isEmpty)
    }

    @Test func editedVersionDoesNotRetargetOldPassagesOrOverwriteHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try ScoreLibrary(directory: directory, profileID: UUID())
        var edited = ScoreExercises.strumming
        let oldID = edited.versionID
        try library.save(passage: .init(versionID: oldID, title: "旧难点", range: .init(firstBar: 0, lastBar: 1)))
        edited.versionID = UUID()
        edited.bars.removeFirst()
        try library.save(score: edited)
        #expect(library.score(versionID: oldID)?.bars.count == 12)
        #expect(library.score(versionID: edited.versionID)?.bars.count == 11)
        #expect(library.passages.first?.versionID == oldID)
        #expect(library.versions(for: edited.id).contains { $0.versionID == oldID })
    }

    @Test func corruptLibraryIsNotSilentlyReplacedWithAnEmptyOne() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = UUID()
        _ = try ScoreLibrary(directory: directory, profileID: profile)
        let url = directory.appendingPathComponent(profile.uuidString + ".json")
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: url)
        #expect(throws: (any Error).self) { try ScoreLibrary(directory: directory, profileID: profile) }
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test func invalidPassageAndChangedImmutableVersionAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try ScoreLibrary(directory: directory, profileID: UUID())
        #expect(throws: (any Error).self) {
            try library.save(passage: .init(versionID: UUID(), title: "错谱", range: .init(firstBar: 0, lastBar: 1)))
        }
        var changed = ScoreExercises.strumming
        changed.title = "不能原地修改"
        #expect(throws: ScoreLibraryError.self) { try library.save(score: changed) }
    }
}
