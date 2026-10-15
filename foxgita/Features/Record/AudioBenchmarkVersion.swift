import Foundation

struct AudioBenchmarkTrack: Equatable, Identifiable {
    let itemId: UUID
    let title: String
    let dayKey: String
    let createdAt: Date
    let clip: PracticeRecordingClip

    var id: String { clip.id }
}

enum AudioBenchmarkReadiness: Equatable {
    case ready(stage: AudioBenchmarkTrack, recent: AudioBenchmarkTrack)
    case needsAnotherRecording
    case selectionUnavailable
    case unavailable
}

enum AudioBenchmarkVersion {
    static let compareLink = String(localized: "录音对比 ›")
    static let needsAnotherCopy = String(localized: "再记录一次即可开启对照")

    static func tracks(
        projectId: UUID,
        items: [PracticeItemSnapshot],
        isPlayable: (PracticeRecordingClip) -> Bool = { clip in
            RecordingStore.fileExists(fileName: clip.fileName)
        }
    ) -> [AudioBenchmarkTrack] {
        items.flatMap { item -> [AudioBenchmarkTrack] in
            guard item.projectId == projectId, !item.isDeleted else { return [] }
            return item.recordings
                .filter { !$0.fileName.isEmpty && !MediaReviewMedia.isVideo(fileName: $0.fileName) && isPlayable($0) }
                .map { clip in
                    AudioBenchmarkTrack(
                        itemId: item.id,
                        title: item.title,
                        dayKey: item.practiceDayKey,
                        createdAt: clip.createdAt,
                        clip: clip
                    )
                }
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    static func resolve(
        stageVersionItemId: UUID?,
        projectId: UUID,
        items: [PracticeItemSnapshot],
        overrideStageClipId: String? = nil,
        overrideRecentClipId: String? = nil,
        isPlayable: (PracticeRecordingClip) -> Bool = { clip in
            RecordingStore.fileExists(fileName: clip.fileName)
        }
    ) -> AudioBenchmarkReadiness {
        let ordered = tracks(projectId: projectId, items: items, isPlayable: isPlayable)
        if let overrideStageClipId, !ordered.contains(where: { $0.clip.id == overrideStageClipId }) {
            return .selectionUnavailable
        }
        if let overrideRecentClipId, !ordered.contains(where: { $0.clip.id == overrideRecentClipId }) {
            return .selectionUnavailable
        }
        guard !ordered.isEmpty else { return .unavailable }

        let stage: AudioBenchmarkTrack
        if let overrideStageClipId, let picked = ordered.first(where: { $0.clip.id == overrideStageClipId }) {
            stage = picked
        } else if let stageVersionItemId, let picked = ordered.first(where: { $0.itemId == stageVersionItemId }) {
            stage = picked
        } else {
            stage = ordered[0]
        }

        if overrideRecentClipId == stage.clip.id { return .selectionUnavailable }
        let others = ordered.filter { $0.clip.id != stage.clip.id }
        let recent: AudioBenchmarkTrack
        if let overrideRecentClipId, let picked = others.first(where: { $0.clip.id == overrideRecentClipId }) {
            recent = picked
        } else if let newest = others.max(by: { $0.clip.createdAt < $1.clip.createdAt }) {
            recent = newest
        } else {
            return .needsAnotherRecording
        }
        return .ready(stage: stage, recent: recent)
    }

}
