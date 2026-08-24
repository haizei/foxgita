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
