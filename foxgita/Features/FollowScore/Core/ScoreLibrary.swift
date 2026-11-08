import Foundation
import Observation

enum ScorePassageStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case toLearn, practicing, mastered
    var id: String { rawValue }
    var title: String {
        switch self { case .toLearn: "待攻克"; case .practicing: "练习中"; case .mastered: "已掌握" }
    }
}
struct ScorePassage: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var versionID: UUID
    var title: String
    var range: ScoreRange
    var speed: Double = 0.75
    var loops: Int = 5
    var note: String = ""
    var status: ScorePassageStatus = .toLearn
    var updatedAt: Date = Date()
}
struct ScoreResume: Codable, Equatable, Sendable {
    var versionID: UUID
    var tick: Int
    var speed: Double
    var range: ScoreRange
    var notation: ScoreNotation = .tablature
    var updatedAt: Date = Date()
}
struct ScorePracticeLink: Codable, Equatable, Sendable {
    var practiceItemID: UUID
    var versionID: UUID
    var range: ScoreRange
    var speed: Double = 0.75
}
struct ScoreSaveCheckpoint: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var runID: UUID
    var practiceItemID: UUID
    var dayKey: String
    var absoluteSeconds: Int
    var runSeconds: Int
    var committed: Bool = false
}
struct ScorePracticeResult: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var practiceItemID: UUID
    var versionID: UUID
    var passageID: UUID?
    var range: ScoreRange
    var speed: Double
    var mode: ScoreRunMode
    var seconds: Int
    var completedLoops: Int
    var judgedEvents: Int
    var expectedEvents: Int
    var pitchAccuracy: Double?
    var rhythmAccuracy: Double?
    var totalScore: Int?
    var createdAt: Date = Date()
    var completePerformance: Bool? = nil
}
enum ScoreLibraryError: Error, LocalizedError {
    case unsupportedVersion, missingScore, immutableVersion, invalidPassage
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "曲谱库版本不兼容，请升级 App。原文件已保留。"
        case .missingScore: "找不到对应曲谱版本，请重新选择。"
        case .immutableVersion: "已确认曲谱不可覆盖，请保存为新版本。"
        case .invalidPassage: "请检查难点名称、小节范围、速度和循环次数。"
        }
    }
}

private struct ScoreLibraryState: Codable {
    var schemaVersion = 1
    var versions: [ScoreDocument] = []
    var archivedScoreIDs: Set<UUID> = []
    var passages: [ScorePassage] = []
    var resumes: [ScoreResume] = []
    var links: [ScorePracticeLink] = []
    var checkpoints: [ScoreSaveCheckpoint] = []
    var results: [ScorePracticeResult] = []
}

@Observable @MainActor final class ScoreLibrary {
    let profileID: UUID
    private let url: URL
    private var state: ScoreLibraryState
    var passages: [ScorePassage] { state.passages.sorted { $0.updatedAt > $1.updatedAt } }
    var resumes: [ScoreResume] { state.resumes.sorted { $0.updatedAt > $1.updatedAt } }
    var links: [ScorePracticeLink] { state.links }
    var checkpoints: [ScoreSaveCheckpoint] { state.checkpoints }
    var results: [ScorePracticeResult] { state.results.sorted { $0.createdAt > $1.createdAt } }
    var scores: [ScoreDocument] {
        var seen = Set<UUID>()
        return state.versions.reversed().filter { !state.archivedScoreIDs.contains($0.id) && seen.insert($0.id).inserted }
    }

    init(directory: URL, profileID: UUID) throws {
        self.profileID = profileID
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(profileID.uuidString + ".json")
        if FileManager.default.fileExists(atPath: url.path) {
            state = try JSONDecoder().decode(ScoreLibraryState.self, from: Data(contentsOf: url))
            guard state.schemaVersion == 1 else { throw ScoreLibraryError.unsupportedVersion }
            for score in state.versions { try score.validate() }
        } else {
            state = .init(versions: ScoreExercises.documents)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        }
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("FollowScore", isDirectory: true)
    }
    func score(versionID: UUID) -> ScoreDocument? { state.versions.first { $0.versionID == versionID } }
    func versions(for scoreID: UUID) -> [ScoreDocument] { state.versions.filter { $0.id == scoreID }.reversed() }
    func link(for practiceItemID: UUID) -> ScorePracticeLink? { state.links.first { $0.practiceItemID == practiceItemID } }
    func resume(for versionID: UUID) -> ScoreResume? { state.resumes.first { $0.versionID == versionID } }
    func hasSource(_ id: UUID) -> Bool { state.versions.contains { $0.sourceID == id } }

    private func update(_ body: (inout ScoreLibraryState) throws -> Void) throws {
        var next = state
        try body(&next)
        let data = try JSONEncoder().encode(next)
        try data.write(to: url, options: .atomic)
        state = next
    }
    func save(score: ScoreDocument) throws {
        try score.validate()
        if let existing = self.score(versionID: score.versionID) {
            guard existing == score else { throw ScoreLibraryError.immutableVersion }
            return
        }
        try update { $0.versions.append(score) }
    }
    func save(passage: ScorePassage) throws {
        guard let score = score(versionID: passage.versionID) else { throw ScoreLibraryError.missingScore }
        _ = try score.tickRange(for: passage.range)
        guard !passage.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              passage.title.count <= 120, passage.note.count <= 4_000,
              passage.speed.isFinite, (0.25...1.5).contains(passage.speed), (1...999).contains(passage.loops) else {
            throw ScoreLibraryError.invalidPassage
        }
        try update { next in
            next.passages.removeAll { $0.id == passage.id }
            next.passages.append(passage)
        }
    }
    func deletePassage(_ id: UUID) throws { try update { $0.passages.removeAll { $0.id == id } } }
    func archiveScore(_ id: UUID) throws { try update { $0.archivedScoreIDs.insert(id) } }
    func save(resume: ScoreResume) throws {
        guard let score = score(versionID: resume.versionID), (0...score.totalTicks).contains(resume.tick),
              resume.speed.isFinite, (0.25...1.5).contains(resume.speed) else { throw ScoreLibraryError.missingScore }
        _ = try score.tickRange(for: resume.range)
        try update { next in next.resumes.removeAll { $0.versionID == resume.versionID }; next.resumes.append(resume) }
    }
    func save(link: ScorePracticeLink) throws {
        if self.link(for: link.practiceItemID) == link { return }
        guard let score = score(versionID: link.versionID) else { throw ScoreLibraryError.missingScore }
        _ = try score.tickRange(for: link.range)
        try update { next in next.links.removeAll { $0.practiceItemID == link.practiceItemID }; next.links.append(link) }
    }
    func save(checkpoint: ScoreSaveCheckpoint) throws {
        guard checkpoint.absoluteSeconds >= 0, checkpoint.runSeconds >= 0 else { throw ScoreLibraryError.invalidPassage }
        try update { next in
            if let i = next.checkpoints.firstIndex(where: { $0.id == checkpoint.id }) {
                guard checkpoint.absoluteSeconds >= next.checkpoints[i].absoluteSeconds else { throw ScoreLibraryError.invalidPassage }
                next.checkpoints[i] = checkpoint
            } else { next.checkpoints.append(checkpoint) }
        }
    }
    func markCommitted(_ id: UUID) throws {
        try update { next in if let i = next.checkpoints.firstIndex(where: { $0.id == id }) { next.checkpoints[i].committed = true } }
    }
    func save(result: ScorePracticeResult) throws {
        guard score(versionID: result.versionID) != nil else { throw ScoreLibraryError.missingScore }
        try update { next in next.results.removeAll { $0.id == result.id }; next.results.append(result) }
    }
}
