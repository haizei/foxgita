import Foundation

enum VideoDiagnosisDraftError: Error, Equatable {
    case emptyField
}

struct VideoFinding: Equatable, Sendable, Codable {
    var startSec: Int
    var endSec: Int
    var title: String
    var evidence: String
    var cause: String
    var action: String
}

struct VideoDiagnosisDraft: Equatable, Sendable {
    var highlight: String
    var focus: String
    var nextAction: String
    var findings: [VideoFinding]

    struct RawFinding: Decodable, Equatable {
        var startSec: Int?
        var endSec: Int?
        var title: String?
        var evidence: String?
        var cause: String?
        var action: String?
    }

    struct Raw: Decodable, Equatable {
        var highlight: String?
        var focus: String?
        var nextAction: String?
        var findings: [RawFinding]?
    }

    static func normalize(_ raw: Raw, durationSec: Int) throws -> VideoDiagnosisDraft {
        let highlight = clampText(raw.highlight)
        let focus = clampText(raw.focus)
        let nextAction = clampText(raw.nextAction)
        guard !highlight.isEmpty, !focus.isEmpty, !nextAction.isEmpty else {
            throw VideoDiagnosisDraftError.emptyField
        }
        let duration = max(durationSec, 0)
        var findings: [VideoFinding] = []
        for item in raw.findings ?? [] {
            let title = clampText(item.title)
            let evidence = clampText(item.evidence)
            let cause = clampText(item.cause)
            let action = clampText(item.action)
            guard !title.isEmpty, !evidence.isEmpty, !cause.isEmpty, !action.isEmpty else {
                continue
            }
            let window = clipWindow(
                start: item.startSec ?? 0,
                end: item.endSec ?? 0,
                durationSec: duration
            )
            findings.append(
                VideoFinding(
                    startSec: window.start,
                    endSec: window.end,
                    title: title,
                    evidence: evidence,
                    cause: cause,
                    action: action
                )
            )
        }
        findings.sort { $0.startSec < $1.startSec }
        if findings.count > 5 {
            findings = Array(findings.prefix(5))
        }
        return VideoDiagnosisDraft(
            highlight: highlight, focus: focus, nextAction: nextAction, findings: findings
        )
    }

    static func clipWindow(start: Int, end: Int, durationSec: Int) -> (start: Int, end: Int) {
        let duration = max(durationSec, 0)
        var s = min(max(start, 0), duration)
        var e = min(max(end, 0), duration)
        if e <= s {
            e = min(s + 20, duration)
        }
        var length = e - s
        length = min(max(length, 10), 30)
        e = min(s + length, duration)
        if duration - s < 10 {
            e = duration
        }
        if e < s { e = s }
        return (s, e)
    }

    private static func clampText(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= 80 ? trimmed : String(trimmed.prefix(80))
    }
}
