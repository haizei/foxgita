import Foundation
import Testing
import UIKit
@testable import foxgita

@MainActor
struct PracticeAttachmentImporterTests {
    enum Failure: Error { case databaseUnavailable }

    @Test func concurrentImageSourcesCannotExceedThreeImages() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let images = NoteImageStore(directory: folder)
        let id = UUID()
        let data = try #require(UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in
            UIColor.orange.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }.pngData())
        try images.add(data, to: id)
        try images.add(data, to: id)
        let added = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<4 { group.addTask { (try? images.add(data, to: id)) != nil } }
            var count = 0
            for await success in group where success { count += 1 }
            return count
        }
        #expect(added == 1)
        #expect(try images.images(for: id).count == 3)
    }

    @Test func cancelledAndCorruptImportsNeverCommitRelations() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("corrupt.wav")
        try Data("not an audio file".utf8).write(to: source)
        let media = folder.appendingPathComponent("Media")
        let importer = PracticeAttachmentImporter(noteImages: NoteImageStore(directory: folder.appendingPathComponent("Images")), mediaDirectory: media)
        var attempts = 0
        do {
            try await importer.importFile(at: source, practiceItemID: UUID()) { _ in attempts += 1 }
            Issue.record("Corrupt audio must be rejected")
        } catch { }
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await importer.importFile(at: source, practiceItemID: UUID()) { _ in attempts += 1 }
                Issue.record("Cancelled import must be rejected")
            } catch is CancellationError { }
            catch { Issue.record("Expected cancellation, got \(error)") }
        }
        await cancelled.value
        #expect(attempts == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: media.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func failedCommitRemovesOnlyImportedCopyAndPreservesSource() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let media = folder.appendingPathComponent("Media")
        let importer = PracticeAttachmentImporter(noteImages: NoteImageStore(directory: folder.appendingPathComponent("Images")), mediaDirectory: media)
        let source = try #require(Bundle.main.url(forResource: "realMetronome-beat", withExtension: "wav"))
        var attempts = 0
        do {
            _ = try await importer.importFile(at: source, practiceItemID: UUID()) { _ in
                attempts += 1
                throw Failure.databaseUnavailable
            }
            Issue.record("Expected the database error")
        } catch Failure.databaseUnavailable { }
        #expect(attempts == 1)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: media.path).isEmpty)
    }
}
