//
//  RecordingStore.swift
//  foxgita
//

import AVFoundation
import Foundation

/// Owns the on-disk side of recordings. The database stores file names only,
/// because the sandbox container path changes between installs.
enum RecordingStore {
    private static let folderName = "Recordings"

    static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func fileExists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    static func newFileName(extension ext: String = "m4a") -> String {
        "rec-\(UUID().uuidString).\(ext)"
    }

    static func byteSize(of url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    static func duration(of url: URL) -> Int {
        if let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 {
            return Int(player.duration.rounded())
        }
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(seconds.rounded())
    }

    /// Photos / HEVC files often report `.invalid` from the sync `duration`
    /// property. Load the key the way AVFoundation requires on iOS 18+.
    static func loadDuration(of url: URL) async -> Int {
        if let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 {
            return Int(player.duration.rounded())
        }
        let asset = AVURLAsset(url: url)
        do {
            let time = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite, seconds > 0 else { return 0 }
            return Int(seconds.rounded())
        } catch {
            return 0
        }
    }

    static func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    private static let mediaExtensions: Set<String> = ["m4a", "mov", "mp4", "m4v"]

    /// Builds before the Recordings subfolder existed wrote clips into the
    /// Documents root. Move them so there is a single place to sweep.
    static func migrateLegacyFiles() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: documents, includingPropertiesForKeys: nil
        )) ?? []
        for file in contents where mediaExtensions.contains(file.pathExtension.lowercased()) {
            let destination = url(for: file.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try? FileManager.default.moveItem(at: file, to: destination)
        }
    }

    /// Deletes clips no `RecordingRef` points at — e.g. a recording made and
    /// then abandoned by leaving the practice screen without finishing.
    @discardableResult
    static func removeOrphans(referenced: Set<String>) -> Int {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        var removed = 0
        for file in contents where mediaExtensions.contains(file.pathExtension.lowercased()) {
            guard !referenced.contains(file.lastPathComponent) else { continue }
            if (try? FileManager.default.removeItem(at: file)) != nil { removed += 1 }
        }
        return removed
    }

    static func removeAll() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        for file in contents where mediaExtensions.contains(file.pathExtension.lowercased()) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
