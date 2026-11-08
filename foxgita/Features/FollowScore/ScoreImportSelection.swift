import Foundation
import ImageIO
import PDFKit
import UIKit

struct ScoreImportSelection: Identifiable {
    let id: UUID
    var pages: [Data]
    var originals: [Data]
    var names: [String]

    static func images(_ data: [Data]) throws -> ScoreImportSelection {
        guard !data.isEmpty, data.count <= 20, data.reduce(0,{ $0+$1.count }) <= 30_000_000 else { throw ScoreRecognitionError.invalidFile }
        let pages = try data.map(thumbnail)
        return .init(id: UUID(),pages: pages,originals: data,names: data.indices.map { "谱页\($0+1)" })
    }
    @MainActor static func files(_ urls: [URL]) async throws -> ScoreImportSelection {
        guard !urls.isEmpty, urls.count <= 20 else { throw ScoreRecognitionError.invalidFile }
        var pages: [Data] = [], originals: [Data] = [], names: [String] = [], total = 0
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size+total <= 30_000_000 else { throw ScoreRecognitionError.invalidFile }
            let data = try Data(contentsOf: url,options: .mappedIfSafe)
            total += data.count
            originals.append(data); names.append(String(url.lastPathComponent.prefix(120)))
            if data.starts(with: Data("%PDF".utf8)) {
                guard let pdf = PDFDocument(data: data), !pdf.isLocked, pdf.pageCount > 0, pdf.pageCount+pages.count <= 20 else { throw ScoreRecognitionError.invalidFile }
                for i in 0..<pdf.pageCount {
                    guard let page = pdf.page(at: i) else { throw ScoreRecognitionError.invalidFile }
                    let bounds = page.bounds(for: .mediaBox)
                    guard bounds.width > 0, bounds.height > 0, bounds.width.isFinite, bounds.height.isFinite else { throw ScoreRecognitionError.invalidFile }
                    let scale = 2048/max(bounds.width,bounds.height)
                    let image = page.thumbnail(of: CGSize(width: bounds.width*scale,height: bounds.height*scale),for: .mediaBox)
                    guard let jpeg = image.jpegData(compressionQuality: 0.85) else { throw ScoreRecognitionError.invalidFile }
                    pages.append(jpeg); await Task.yield()
                }
            } else { pages.append(try thumbnail(data)) }
            guard pages.count <= 20 else { throw ScoreRecognitionError.invalidFile }
        }
        return .init(id: UUID(),pages: pages,originals: originals,names: names)
    }
    private static func thumbnail(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData,nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,height > 0,width <= 20_000,height <= 20_000,width*height <= 40_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:2048
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { throw ScoreRecognitionError.invalidFile }
        return jpeg
    }
}

@MainActor enum ScoreSourceVault {
    struct Pending: Identifiable { var id: UUID; var title: String; var pageCount: Int }
    /// This file exists only after the user consents to upload to this destination.
    struct RecognitionRequest: Codable, Equatable {
        enum Phase: String, Codable { case active, needsRetry, cancelling }
        var destination: URL
        var requestID: UUID
        var jobID: UUID?
        var phase: Phase = .active
    }

    static func recognitionRequest(profileID: UUID, sourceID: UUID) throws -> RecognitionRequest? {
        let url = directory(profileID: profileID, sourceID: sourceID).appendingPathComponent("request.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(RecognitionRequest.self, from: Data(contentsOf: url))
    }

    static func saveRequest(_ request: RecognitionRequest?, profileID: UUID, sourceID: UUID) throws {
        let url = directory(profileID: profileID, sourceID: sourceID).appendingPathComponent("request.json")
        if let request {
            try JSONEncoder().encode(request).write(to: url, options: .atomic)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func directory(profileID: UUID,sourceID: UUID) -> URL {
        ScoreLibrary.defaultDirectory.appendingPathComponent("Sources").appendingPathComponent(profileID.uuidString).appendingPathComponent(sourceID.uuidString)
    }
    static func save(_ selection: ScoreImportSelection,profileID: UUID) throws {
        let directory = directory(profileID: profileID,sourceID: selection.id)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        for (i,data) in selection.pages.enumerated() { try data.write(to: directory.appendingPathComponent("page-\(i).jpg"),options: .atomic) }
        for (i,data) in selection.originals.enumerated() { try data.write(to: directory.appendingPathComponent("original-\(i).data"),options: .atomic) }
        try JSONEncoder().encode(selection.names).write(to: directory.appendingPathComponent("names.json"),options: .atomic)
    }
    static func pages(profileID: UUID,sourceID: UUID) throws -> [Data] {
        let directory = directory(profileID: profileID,sourceID: sourceID)
        let urls = try FileManager.default.contentsOfDirectory(at: directory,includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("page-") && $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return try urls.map { try Data(contentsOf: $0) }
    }
    static func pending(profileID: UUID,library: ScoreLibrary) throws -> [Pending] {
        let root = ScoreLibrary.defaultDirectory.appendingPathComponent("Sources").appendingPathComponent(profileID.uuidString)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root,includingPropertiesForKeys: nil).compactMap { url in
            guard let id = UUID(uuidString: url.lastPathComponent), !library.hasSource(id) else { return nil }
            let names = try JSONDecoder().decode([String].self,from: Data(contentsOf: url.appendingPathComponent("names.json")))
            let count = try FileManager.default.contentsOfDirectory(atPath: url.path).filter { $0.hasPrefix("page-") && $0.hasSuffix(".jpg") }.count
            return Pending(id: id,title: names.first ?? "待识谱原件",pageCount: count)
        }
    }
    static func restore(profileID: UUID,sourceID: UUID) throws -> ScoreImportSelection {
        let directory = directory(profileID: profileID,sourceID: sourceID)
        let names = try JSONDecoder().decode([String].self,from: Data(contentsOf: directory.appendingPathComponent("names.json")))
        let originals = try names.indices.map { try Data(contentsOf: directory.appendingPathComponent("original-\($0).data")) }
        return .init(id: sourceID,pages: try pages(profileID: profileID,sourceID: sourceID),originals: originals,names: names)
    }
    static func saveDraft(_ draft: RecognizedScoreDraft,profileID: UUID,sourceID: UUID) throws {
        try JSONEncoder().encode(draft).write(to: directory(profileID: profileID,sourceID: sourceID).appendingPathComponent("draft.json"),options: .atomic)
    }
    static func draft(profileID: UUID,sourceID: UUID) throws -> RecognizedScoreDraft? {
        let url = directory(profileID: profileID,sourceID: sourceID).appendingPathComponent("draft.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(RecognizedScoreDraft.self,from: Data(contentsOf: url))
    }
}
