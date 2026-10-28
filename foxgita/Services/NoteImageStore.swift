import Foundation
import ImageIO
import UIKit

nonisolated struct NoteImage: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
}

/// Files are scoped to the practice item, which is the record used by the current practice flow.
nonisolated struct NoteImageStore: Sendable {
    enum StoreError: Error {
        case invalidImage
        case limitReached
        case notFound
    }

    static let maximumImages = 3
    private static let additionLock = NSLock()
    let directory: URL

    init(directory: URL = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appendingPathComponent(PracticeTestEnvironment.isActive ? "TestNoteImages" : "NoteImages", isDirectory: true)) {
        self.directory = directory
    }

    func images(for itemId: UUID) throws -> [NoteImage] {
        let folder = directory.appendingPathComponent(itemId.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "jpg" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { NoteImage(id: $0.lastPathComponent, url: $0) }
    }

    @discardableResult
    func add(_ data: Data, to itemId: UUID) throws -> NoteImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw StoreError.invalidImage }
        return try add(source, to: itemId)
    }

    func add(contentsOf url: URL, to itemId: UUID) throws -> NoteImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw StoreError.invalidImage }
        return try add(source, to: itemId)
    }

    private func add(_ source: CGImageSource, to itemId: UUID) throws -> NoteImage {
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
            ] as CFDictionary),
              let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.82)
        else { throw StoreError.invalidImage }

        // Decode before locking; only the short quota check and atomic file
        // commit are serialized across PhotosPicker, camera and file imports.
        Self.additionLock.lock()
        defer { Self.additionLock.unlock() }
        guard try images(for: itemId).count < Self.maximumImages else { throw StoreError.limitReached }
        let folder = directory.appendingPathComponent(itemId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = String(format: "%013d", Int(Date().timeIntervalSince1970 * 1000))
            + "-" + UUID().uuidString + ".jpg"
        let url = folder.appendingPathComponent(name)
        try jpeg.write(to: url, options: .atomic)
        return NoteImage(id: name, url: url)
    }

    func remove(_ image: NoteImage, from itemId: UUID) throws {
        guard let stored = try images(for: itemId).first(where: { $0.id == image.id }) else {
            throw StoreError.notFound
        }
        try FileManager.default.removeItem(at: stored.url)
    }

    func removeImages(for itemId: UUID) throws {
        let folder = directory.appendingPathComponent(itemId.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    func removeAll() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

}
