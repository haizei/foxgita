import Foundation
import Testing
import UIKit
@testable import foxgita

struct NoteImageStoreTests {
    @Test func imagesSurviveReopeningAndRespectThreeImageLimit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteImageStore(directory: root)
        let itemId = UUID()
        let data = try #require(UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
            .image { _ in UIColor.orange.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 20, height: 20)) }
            .pngData())

        let first = try store.add(data, to: itemId)
        try store.add(data, to: itemId)
        try store.add(data, to: itemId)
        #expect(try NoteImageStore(directory: root).images(for: itemId).count == 3)
        #expect(throws: NoteImageStore.StoreError.limitReached) {
            try store.add(data, to: itemId)
        }

        try store.remove(first, from: itemId)
        #expect(try store.images(for: itemId).count == 2)
        #expect(try store.images(for: UUID()).isEmpty)
    }

    @Test func deletingOnePracticeDoesNotRemoveAnotherPracticesImages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteImageStore(directory: root)
        let data = try #require(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
            .image { _ in UIColor.blue.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 4, height: 4)) }
            .pngData())
        let live = UUID(), deleted = UUID()
        try store.add(data, to: live)
        try store.add(data, to: deleted)

        try store.removeImages(for: deleted)
        #expect(try store.images(for: live).count == 1)
        #expect(try store.images(for: deleted).isEmpty)
    }
}
