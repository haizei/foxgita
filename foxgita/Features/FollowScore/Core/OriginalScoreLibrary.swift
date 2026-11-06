import Foundation
import Observation

nonisolated struct OriginalScoreDraft: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var document: OriginalScoreDocument
    var baseVersionID: UUID?
    var updatedAt = Date()
}

nonisolated struct OriginalScorePracticeRecord: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var practiceItemID: UUID
    var versionID: UUID
    var range: OriginalScoreRange
    var bpm: Double
    var seconds: Double
    var date = Date()
}

private struct OriginalScoreLibraryState: Codable {
    var schemaVersion = 1
    var drafts: [OriginalScoreDraft] = []
    var versions: [OriginalScoreDocument] = []
    var hidden: Set<UUID> = []
    var progress: [OriginalScoreProgress] = []
    var publishedDrafts: [UUID: UUID] = [:]
    var records: [OriginalScorePracticeRecord] = []
    var checkpoints: [ScoreSaveCheckpoint] = []
}

@Observable @MainActor final class OriginalScoreLibrary {
    let profileID: UUID
    private let url: URL
    private var state: OriginalScoreLibraryState

    var drafts: [OriginalScoreDraft] { state.drafts.sorted { $0.updatedAt > $1.updatedAt } }
    var records: [OriginalScorePracticeRecord] { state.records.sorted { $0.date > $1.date } }
    var pendingCheckpoints: [ScoreSaveCheckpoint] { state.checkpoints.filter { !$0.committed } }
    var documents: [OriginalScoreDocument] {
        var seen = Set<UUID>()
        return state.versions.reversed().filter { !state.hidden.contains($0.id) && seen.insert($0.id).inserted }
    }

    init(directory: URL, profileID: UUID) throws {
        self.profileID = profileID
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(profileID.uuidString + "-original.json")
        if FileManager.default.fileExists(atPath: url.path) {
            state = try JSONDecoder().decode(OriginalScoreLibraryState.self, from: Data(contentsOf: url))
            guard state.schemaVersion == 1 else { throw OriginalScoreError.unsupportedVersion }
            for document in state.versions { try document.validate() }
        } else { state = .init() }
    }

    func version(_ id: UUID) -> OriginalScoreDocument? { state.versions.first { $0.versionID == id } }
    func progress(for versionID: UUID) -> OriginalScoreProgress? { state.progress.first { $0.versionID == versionID } }

    private func update(_ change: (inout OriginalScoreLibraryState) throws -> Void) throws {
        var next = state
        try change(&next)
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        state = next
    }

    func save(draft: OriginalScoreDraft) throws {
        if let existing = state.drafts.first(where: { $0.id == draft.id }), existing.updatedAt > draft.updatedAt { return }
        try update { next in
            next.drafts.removeAll { $0.id == draft.id }
            next.drafts.append(draft)
        }
    }

    func discardDraft(_ id: UUID) throws { try update { $0.drafts.removeAll { $0.id == id } } }

    func beginRevision(_ document: OriginalScoreDocument) throws -> OriginalScoreDraft {
        guard documents.contains(where: { $0.versionID == document.versionID }) else { throw OriginalScoreError.conflict }
        var next = document
        next.versionID = UUID(); next.parentVersionID = document.versionID; next.createdAt = Date()
        let draft = OriginalScoreDraft(document: next, baseVersionID: document.versionID)
        try save(draft: draft)
        return draft
    }

    @discardableResult func publish(draftID: UUID, availablePages: Int) throws -> OriginalScoreDocument {
        if let id = state.publishedDrafts[draftID], let document = version(id) { return document }
        guard let draft = state.drafts.first(where: { $0.id == draftID }) else { throw OriginalScoreError.missingVersion }
        let document = draft.document
        try document.validate()
        guard availablePages == document.pageCount else { throw OriginalScoreError.missingVersion }
        let current = state.versions.last { $0.id == document.id }
        guard current?.versionID == draft.baseVersionID, !state.hidden.contains(document.id),
              version(document.versionID) == nil else { throw OriginalScoreError.conflict }
        let oldProgress = current.flatMap { progress(for: $0.versionID) }
        var migrated: OriginalScoreProgress?
        if let current, var progress = oldProgress {
            progress.versionID = document.versionID
            if !document.hasSameTiming(as: current) {
                guard let range = document.fullRange else { throw OriginalScoreError.invalidRange }
                progress.range = range; progress.rowID = range.first; progress.rowBeat = 0
                progress.looping = false; progress.finished = false
            }
            migrated = progress
        }
        try update { next in
            next.versions.append(document)
            next.drafts.removeAll { $0.id == draftID }
            next.publishedDrafts[draftID] = document.versionID
            if let migrated { next.progress.append(migrated) }
        }
        return document
    }

    func save(progress: OriginalScoreProgress) throws {
        guard let document = version(progress.versionID) else { throw OriginalScoreError.missingVersion }
        _ = try OriginalScoreRun(document: document, progress: progress)
        guard let row = document.rows.first(where: { $0.id == progress.rowID }),
              progress.rowBeat.isFinite, (0...row.beats).contains(progress.rowBeat) else { throw OriginalScoreError.invalidRange }
        try update { next in
            next.progress.removeAll { $0.versionID == progress.versionID }
            next.progress.append(progress)
        }
    }
    func hide(_ materialID: UUID) throws { try update { $0.hidden.insert(materialID) } }

    func save(record: OriginalScorePracticeRecord) throws {
        guard let document = version(record.versionID), record.seconds.isFinite, record.seconds >= 0,
              record.bpm.isFinite, (40...200).contains(record.bpm) else { throw OriginalScoreError.missingVersion }
        _ = try document.indices(for: record.range)
        if let old = state.records.first(where: { $0.id == record.id }), record.seconds < old.seconds { throw OriginalScoreError.conflict }
        try update { next in next.records.removeAll { $0.id == record.id }; next.records.append(record) }
    }

    func save(checkpoint: ScoreSaveCheckpoint) throws {
        guard checkpoint.absoluteSeconds >= 0, checkpoint.runSeconds >= 0 else { throw OriginalScoreError.invalidDocument }
        if let old = state.checkpoints.first(where: { $0.id == checkpoint.id }),
           checkpoint.absoluteSeconds < old.absoluteSeconds { throw OriginalScoreError.conflict }
        try update { next in next.checkpoints.removeAll { $0.id == checkpoint.id }; next.checkpoints.append(checkpoint) }
    }
    func markCommitted(_ id: UUID) throws {
        try update { next in
            if let index = next.checkpoints.firstIndex(where: { $0.id == id }) { next.checkpoints[index].committed = true }
        }
    }

    /// The duration journal and its historical material association become
    /// durable together, before the external PracticeStore commit.
    func save(checkpoint: ScoreSaveCheckpoint, record: OriginalScorePracticeRecord) throws {
        guard checkpoint.practiceItemID == record.practiceItemID,
              checkpoint.absoluteSeconds >= 0, checkpoint.runSeconds >= 0,
              let document = version(record.versionID), record.seconds.isFinite, record.seconds > 0,
              record.bpm.isFinite, (40...200).contains(record.bpm) else { throw OriginalScoreError.invalidDocument }
        _ = try document.indices(for: record.range)
        if let old = state.checkpoints.first(where: { $0.id == checkpoint.id }), checkpoint.absoluteSeconds < old.absoluteSeconds {
            throw OriginalScoreError.conflict
        }
        if let old = state.records.first(where: { $0.id == record.id }), record.seconds < old.seconds {
            throw OriginalScoreError.conflict
        }
        try update { next in
            next.records.removeAll { $0.id == record.id }; next.records.append(record)
            next.checkpoints.removeAll { $0.id == checkpoint.id }; next.checkpoints.append(checkpoint)
        }
    }
}
