import AVFoundation
import Foundation
import UniformTypeIdentifiers

nonisolated enum ImportedPracticeAttachment: Sendable {
    case image(NoteImage)
    case media(AudioRecorderService.Clip)
}

@MainActor
struct PracticeAttachmentImporter {
    nonisolated enum ImportError: LocalizedError {
        case unsupported, unreadable, cleanupFailed
        var errorDescription: String? {
            switch self {
            case .unsupported: String(localized: "请选择图片、音频或视频文件")
            case .unreadable: String(localized: "文件无法读取或格式不受支持")
            case .cleanupFailed: String(localized: "导入未完成，临时文件清理失败，请重试")
            }
        }
    }

    var noteImages = NoteImageStore()
    var mediaDirectory = RecordingStore.directory

    @discardableResult
    func importFile(
        at source: URL, practiceItemID: UUID,
        save: (ImportedPracticeAttachment) throws -> Void
    ) async throws -> ImportedPracticeAttachment {
        let images = noteImages
        let directory = mediaDirectory
        let preparation = Task.detached(priority: .userInitiated) {
            try await Self.prepare(source, itemID: practiceItemID, images: images, directory: directory)
        }
        let attachment = try await withTaskCancellationHandler {
            try await preparation.value
        } onCancel: { preparation.cancel() }
        do {
            try Task.checkCancellation()
            try save(attachment)
            return attachment
        } catch {
            let failure = error
            try await Task.detached {
                do { try Self.remove(attachment, itemID: practiceItemID, images: images, directory: directory) }
                catch { throw ImportError.cleanupFailed }
            }.value
            throw failure
        }
    }

    private nonisolated static func prepare(
        _ source: URL, itemID: UUID, images: NoteImageStore, directory: URL
    ) async throws -> ImportedPracticeAttachment {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        guard let type = UTType(filenameExtension: source.pathExtension) else { throw ImportError.unsupported }
        if type.conforms(to: .image) {
            let image = try images.add(contentsOf: source, to: itemID)
            // The caller checks cancellation before committing and compensates this file.
            return .image(image)
        }
        guard type.conforms(to: .audio) || type.conforms(to: .movie) else { throw ImportError.unsupported }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "rec-\(UUID().uuidString).\(source.pathExtension.lowercased())"
        let destination = directory.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            let asset = AVURLAsset(url: destination)
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration).seconds
            guard playable, duration.isFinite, duration > 0 else { throw ImportError.unreadable }
            try Task.checkCancellation()
            let bytes = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return .media(AudioRecorderService.Clip(
                id: UUID().uuidString, fileName: name, bytes: bytes, durationSec: Int(duration.rounded()),
                createdAt: Date(), label: source.deletingPathExtension().lastPathComponent
            ))
        } catch {
            if FileManager.default.fileExists(atPath: destination.path) {
                do { try FileManager.default.removeItem(at: destination) }
                catch { throw ImportError.cleanupFailed }
            }
            throw error
        }
    }

    private nonisolated static func remove(
        _ attachment: ImportedPracticeAttachment, itemID: UUID, images: NoteImageStore, directory: URL
    ) throws {
        switch attachment {
        case .image(let image): try images.remove(image, from: itemID)
        case .media(let clip): try FileManager.default.removeItem(at: directory.appendingPathComponent(clip.fileName))
        }
    }
}
