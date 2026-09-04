import Foundation

struct ResumeSession: Equatable {
    var id: String
    var endedAt: Date
    var bpm: Int
    var noteText: String
    var deletedAt: Date?
    var durationSec: Int
    var recordingCount: Int
    var startedAt: Date
}

struct ResumeRecording: Equatable {
    var id: String
    var createdAt: Date
    var deletedAt: Date?
    var reviewNextAction: String
}

struct ResumeState: Equatable {
    var bpm: Int
    var focus: String?
    var hasHistory: Bool
    var openSessionId: String? = nil
    var durationSec: Int = 0
    var noteText: String = ""
    var startedAt: Date? = nil
}

enum PracticeResumeQuery {
    static func resume(
        sessions: [ResumeSession],
        recordings: [ResumeRecording],
        defaultBpm: Int,
        skippedSessionId: String? = nil
    ) -> ResumeState {
        let live = sessions.filter { $0.deletedAt == nil }
        let effective = live.filter {
            PracticeRecordRules.isEffective(
                durationSec: $0.durationSec,
                noteText: $0.noteText,
                recordingCount: $0.recordingCount
            )
        }
        .sorted { $0.endedAt > $1.endedAt }

        let hasHistory = !effective.isEmpty
        let rawBpm = effective.first?.bpm ?? defaultBpm
        let bpm = min(200, max(40, rawBpm))

        let nextAction = recordings
            .filter { $0.deletedAt == nil }
            .filter { !$0.reviewNextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.createdAt > $1.createdAt }
            .first?
            .reviewNextAction

        let focus: String?
        if let nextAction {
            focus = nextAction
        } else if let note = effective.first?.noteText {
            focus = Self.notePreview(note)
        } else {
            focus = nil
        }

        let newest = effective.first
        let canContinue: Bool = {
            guard let newest else { return false }
            if let skippedSessionId, newest.id == skippedSessionId { return false }
            return true
        }()

        return ResumeState(
            bpm: bpm,
            focus: focus,
            hasHistory: hasHistory,
            openSessionId: canContinue ? newest?.id : nil,
            durationSec: canContinue ? (newest?.durationSec ?? 0) : 0,
            noteText: canContinue ? (newest?.noteText ?? "") : "",
            startedAt: canContinue ? newest?.startedAt : nil
        )
    }

    static func focusLine(state: ResumeState) -> String? {
        guard state.hasHistory else { return nil }
        if let focus = state.focus, !focus.isEmpty {
            return String(localized: "上次 \(state.bpm) BPM · \(focus)")
        }
        return String(localized: "上次练到 \(state.bpm) BPM")
    }

    private static func notePreview(_ note: String) -> String? {
        let first = note
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !first.isEmpty else { return nil }
        if first.count > 28 {
            return String(first.prefix(28)) + "…"
        }
        return first
    }
}

struct PracticeLineageItem: Equatable {
    var id: UUID
    var originId: String?
    var title: String
    var sourceRaw: String
    var bpm: Int?
    var note: String
    var durationSeconds: Int
    var recordingCount: Int
    var createdAt: Date
    var deletedAt: Date?
}

enum PracticeItemResumeQuery {
    static func lineage(
        currentId: UUID,
        originId: String?,
        title: String,
        sourceRaw: String,
        items: [PracticeLineageItem]
    ) -> [PracticeLineageItem] {
        let live = items.filter { $0.deletedAt == nil && $0.id != currentId }
        let origin = originId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !origin.isEmpty {
            let matched = live.filter {
                ($0.originId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") == origin
            }
            if !matched.isEmpty { return matched }
        }
        return live.filter { $0.title == title && $0.sourceRaw == sourceRaw }
    }

    static func resume(
        current: PracticeLineageItem,
        items: [PracticeLineageItem],
        recordings: [ResumeRecording],
        defaultBpm: Int
    ) -> ResumeState {
        var sessions = lineage(
            currentId: current.id,
            originId: current.originId,
            title: current.title,
            sourceRaw: current.sourceRaw,
            items: items
        ).map(session(from:))
        if isEffective(current) {
            sessions.append(session(from: current))
        }
        return PracticeResumeQuery.resume(
            sessions: sessions,
            recordings: recordings,
            defaultBpm: current.bpm ?? defaultBpm
        )
    }

    static func seedBpm(
        originId: String?,
        title: String,
        sourceRaw: String,
        items: [PracticeLineageItem],
        fallback: Int?
    ) -> Int? {
        let siblings = lineage(
            currentId: UUID(),
            originId: originId,
            title: title,
            sourceRaw: sourceRaw,
            items: items
        )
        let state = PracticeResumeQuery.resume(
            sessions: siblings.map(session(from:)),
            recordings: [],
            defaultBpm: fallback ?? 80
        )
        return state.hasHistory ? state.bpm : fallback
    }

    static func lineageItem(from item: PracticeItem) -> PracticeLineageItem {
        PracticeLineageItem(
            id: item.id,
            originId: item.originId,
            title: item.title,
            sourceRaw: item.sourceRaw,
            bpm: item.bpm,
            note: item.note,
            durationSeconds: item.durationSeconds,
            recordingCount: item.recordings.filter { $0.deletedAt == nil }.count,
            createdAt: item.createdAt,
            deletedAt: item.deletedAt
        )
    }

    static func recordings(from items: [PracticeItem]) -> [ResumeRecording] {
        items.flatMap { item in
            item.recordings.map { rec in
                ResumeRecording(
                    id: rec.id,
                    createdAt: rec.createdAt,
                    deletedAt: rec.deletedAt,
                    reviewNextAction: rec.reviewNextAction
                )
            }
        }
    }

    private static func isEffective(_ item: PracticeLineageItem) -> Bool {
        guard item.deletedAt == nil else { return false }
        return PracticeRecordRules.isEffective(
            durationSec: item.durationSeconds,
            noteText: item.note,
            recordingCount: item.recordingCount
        )
    }

    private static func session(from item: PracticeLineageItem) -> ResumeSession {
        ResumeSession(
            id: item.id.uuidString,
            endedAt: item.createdAt,
            bpm: item.bpm ?? 80,
            noteText: item.note,
            deletedAt: item.deletedAt,
            durationSec: item.durationSeconds,
            recordingCount: item.recordingCount,
            startedAt: item.createdAt
        )
    }
}
