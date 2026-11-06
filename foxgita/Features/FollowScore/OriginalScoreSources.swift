import Foundation

@MainActor enum OriginalScoreSources {
    static func directory(profileID: UUID, sourceID: UUID) -> URL {
        ScoreLibrary.defaultDirectory.appendingPathComponent("OriginalSources")
            .appendingPathComponent(profileID.uuidString).appendingPathComponent(sourceID.uuidString)
    }

    static func save(_ selection: ScoreImportSelection, profileID: UUID) throws {
        let root = directory(profileID: profileID, sourceID: selection.id)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (index, data) in selection.pages.enumerated() {
            try data.write(to: root.appendingPathComponent("page-\(index).jpg"), options: .atomic)
        }
        for (index, data) in selection.originals.enumerated() {
            try data.write(to: root.appendingPathComponent("original-\(index).data"), options: .atomic)
        }
        try JSONEncoder().encode(selection.names).write(to: root.appendingPathComponent("names.json"), options: .atomic)
    }

    static func pages(for document: OriginalScoreDocument, profileID: UUID) throws -> [Data] {
        try (0..<document.pageCount).map {
            try Data(contentsOf: directory(profileID: profileID, sourceID: document.sourceID)
                .appendingPathComponent("page-\($0).jpg"))
        }
    }
}

@MainActor enum OriginalScoreLibraryProvider {
    private static var libraries: [UUID: OriginalScoreLibrary] = [:]
    static func library(profileID: UUID) throws -> OriginalScoreLibrary {
        if let library = libraries[profileID] { return library }
        let library = try OriginalScoreLibrary(directory: ScoreLibrary.defaultDirectory, profileID: profileID)
        libraries[profileID] = library
        return library
    }
}

extension PracticeStore {
    func openOriginalScorePractice(document: OriginalScoreDocument, bpm: Double, preferred: UUID?,
                                   completed: Set<UUID>, now: Date, calendar: Calendar) throws -> PracticeItem {
        let profile = try scoreProfileID()
        let day = PracticeDayKey.make(from: now, calendar: calendar)
        if let preferred, let item = try? scorePracticeItem(id: preferred),
           item.practiceDayKey == day, !completed.contains(item.id) { return item }
        let origin = "original-score:\(document.id.uuidString)"
        if let existing = try practiceItemSnapshots(profileId: profile).first(where: {
            !$0.isDeleted && $0.practiceDayKey == day && $0.originId == origin && !completed.contains($0.id)
        }) { return try scorePracticeItem(id: existing.id) }
        return try createPracticeItem(input: .init(title: document.title, category: .song, source: .custom,
            originId: origin, bpm: Int(bpm.rounded()), timeSignature: "\(document.numerator)/\(document.denominator)",
            subtitle: "原谱跟弹", targetMin: 10), now: now, calendar: calendar)
    }
}
