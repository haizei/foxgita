import Foundation

enum AlbumVideoImporterError: Error, Equatable {
    case missingSource
    case unsupportedExtension
    case copyFailed
}

enum AlbumVideoImporter {
    static let allowedExtensions: Set<String> = ["mov", "mp4", "m4v"]

    @MainActor
    static func importClip(from source: URL, label: String = "") throws -> VideoRecorderService.Clip {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw AlbumVideoImporterError.missingSource
        }
        let ext = source.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw AlbumVideoImporterError.unsupportedExtension
        }
        let name = RecordingStore.newFileName(extension: ext)
        let dest = RecordingStore.url(for: name)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            return VideoRecorderService.Clip(
                id: UUID().uuidString,
                fileName: name,
                bytes: RecordingStore.byteSize(of: dest),
                durationSec: RecordingStore.duration(of: dest),
                createdAt: Date(),
                label: label.isEmpty ? String(localized: "视频") : label
            )
        } catch {
            RecordingStore.delete(fileName: name)
            throw AlbumVideoImporterError.copyFailed
        }
    }
}
