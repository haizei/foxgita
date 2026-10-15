import Foundation

struct AudioBenchmarkTrack: Equatable, Identifiable {
    let itemId: UUID
    let title: String
    let dayKey: String
    let createdAt: Date
    let clip: PracticeRecordingClip

    var id: UUID { itemId }
}

enum AudioBenchmarkReadiness: Equatable {
    case ready(stage: AudioBenchmarkTrack, recent: AudioBenchmarkTrack)
    case needsAnotherRecording
    case unavailable
}

enum AudioBenchmarkVersion {
    static let compareLink = "与阶段版对照 ›"
    static let needsAnotherCopy = "再记录一次即可开启对照"
    static let sameFragmentNote = "ⓘ 两次均为用户确认的同一片段"

    static func tracks(projectId: UUID, items: [PracticeItemSnapshot]) -> [AudioBenchmarkTrack] {
        items.compactMap { item in
            guard item.projectId == projectId, !item.isDeleted else { return nil }
            guard let clip = item.recordings.first(where: { !$0.fileName.isEmpty }) else { return nil }
            return AudioBenchmarkTrack(
                itemId: item.id,
                title: item.title,
                dayKey: item.practiceDayKey,
                createdAt: item.createdAt,
                clip: clip
            )
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    static func resolve(
        stageVersionItemId: UUID?,
        projectId: UUID,
        items: [PracticeItemSnapshot],
        overrideStageItemId: UUID? = nil,
        overrideRecentItemId: UUID? = nil
    ) -> AudioBenchmarkReadiness {
        let ordered = tracks(projectId: projectId, items: items)
        guard !ordered.isEmpty else { return .unavailable }

        let stage: AudioBenchmarkTrack
        if let overrideStageItemId, let picked = ordered.first(where: { $0.itemId == overrideStageItemId }) {
            stage = picked
        } else if let stageVersionItemId, let picked = ordered.first(where: { $0.itemId == stageVersionItemId }) {
            stage = picked
        } else {
            stage = ordered[0]
        }

        let others = ordered.filter { $0.itemId != stage.itemId }
        let recent: AudioBenchmarkTrack
        if let overrideRecentItemId, let picked = others.first(where: { $0.itemId == overrideRecentItemId }) {
            recent = picked
        } else if let newest = others.max(by: { $0.createdAt < $1.createdAt }) {
            recent = newest
        } else {
            return .needsAnotherRecording
        }
        return .ready(stage: stage, recent: recent)
    }

    static func listenHeadline(focus: String) -> String {
        focus.contains("副歌") ? "听听这段副歌的变化" : "听听这段的变化"
    }

    static func subtitle(projectName: String, focus: String) -> String {
        let trimmed = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return projectName }
        return "\(projectName) · \(trimmed)"
    }

    static func spanLine(stageDayKey: String, recentDayKey: String) -> String {
        "\(ProgressFirstFormat.monthDay(stageDayKey)) 阶段版 → \(ProgressFirstFormat.monthDay(recentDayKey)) 最近录音"
    }
}
