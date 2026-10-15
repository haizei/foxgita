import Foundation

struct ProjectNoteEntry: Equatable, Identifiable {
    let itemId: UUID
    let createdAt: Date
    let dayKey: String
    let title: String
    let body: String
    let hasRecording: Bool

    var id: UUID { itemId }
}

enum ProjectNoteProjection {
    static let previewLimit = 3
    static let footer = String(localized: "ⓘ 笔记来自每次练习，可在原练习记录中修改")

    static func entries(
        projectId: UUID,
        items: [PracticeItemSnapshot],
        isPlayable: (PracticeRecordingClip) -> Bool = { clip in
            RecordingStore.fileExists(fileName: clip.fileName)
        }
    ) -> [ProjectNoteEntry] {
        items.compactMap { item in
            guard item.projectId == projectId, !item.isDeleted else { return nil }
            let body = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            let hasRecording = item.recordings.contains {
                !$0.fileName.isEmpty && !MediaReviewMedia.isVideo(fileName: $0.fileName) && isPlayable($0)
            }
            return ProjectNoteEntry(
                itemId: item.id,
                createdAt: item.createdAt,
                dayKey: item.practiceDayKey,
                title: item.title,
                body: body,
                hasRecording: hasRecording
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func preview(
        projectId: UUID,
        items: [PracticeItemSnapshot],
        isPlayable: (PracticeRecordingClip) -> Bool = { clip in
            RecordingStore.fileExists(fileName: clip.fileName)
        }
    ) -> [ProjectNoteEntry] {
        Array(entries(projectId: projectId, items: items, isPlayable: isPlayable).prefix(previewLimit))
    }

    static func comparisonCitation(cited: Int, total: Int) -> String {
        String(localized: "本次对比引用 \(cited) 条 · 项目共 \(total) 条")
    }
}
