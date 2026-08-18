import Foundation
import Testing
@testable import foxgita

@MainActor
struct AlbumVideoImporterTests {
    @Test func copiesAndKeepsExtension() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("src-\(UUID().uuidString).mp4")
        try Data([0x00, 0x01]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let clip = try AlbumVideoImporter.importClip(from: source, label: "和弦转换")
        defer { RecordingStore.delete(fileName: clip.fileName) }

        #expect(clip.fileName.hasSuffix(".mp4"))
        #expect(clip.bytes == 2)
        #expect(clip.label == "和弦转换")
        #expect(FileManager.default.fileExists(atPath: RecordingStore.url(for: clip.fileName).path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func missingSourceThrows() {
        let missing = URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString).mov")
        #expect(throws: AlbumVideoImporterError.missingSource) {
            try AlbumVideoImporter.importClip(from: missing)
        }
    }

    @Test func rejectsIllegalExtensionAndWritesNothing() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("note-\(UUID().uuidString).txt")
        try Data([0x00]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let before = (try? FileManager.default.contentsOfDirectory(
            at: RecordingStore.directory, includingPropertiesForKeys: nil
        )) ?? []
        #expect(throws: AlbumVideoImporterError.unsupportedExtension) {
            try AlbumVideoImporter.importClip(from: source)
        }
        let after = (try? FileManager.default.contentsOfDirectory(
            at: RecordingStore.directory, includingPropertiesForKeys: nil
        )) ?? []
        #expect(Set(after.map(\.lastPathComponent)) == Set(before.map(\.lastPathComponent)))
    }

    @Test func orphanSweepRemovesUnreferencedM4v() throws {
        let name = "orphan-\(UUID().uuidString).m4v"
        try Data([0x00]).write(to: RecordingStore.url(for: name))
        defer { RecordingStore.delete(fileName: name) }
        let removed = RecordingStore.removeOrphans(referenced: [])
        #expect(removed >= 1)
        #expect(!FileManager.default.fileExists(atPath: RecordingStore.url(for: name).path))
    }

    @Test func stagePreviewCopiesOutOfInboxAndKeepsExtension() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("dji_mimo_\(UUID().uuidString).mov")
        try Data([0x00, 0x01, 0x02]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let staged = try AlbumVideoImporter.stagePreview(from: source)
        defer { try? FileManager.default.removeItem(at: staged) }

        #expect(staged.lastPathComponent.hasPrefix("album-preview-"))
        #expect(staged.pathExtension.lowercased() == "mov")
        #expect(RecordingStore.byteSize(of: staged) == 3)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(staged.path != source.path)
    }

    @Test func loadDurationReturnsZeroForJunkBytes() async {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("junk-\(UUID().uuidString).mov")
        try? Data([0x00]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let seconds = await RecordingStore.loadDuration(of: source)
        #expect(seconds == 0)
    }
}
