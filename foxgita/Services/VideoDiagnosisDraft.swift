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

    static func normalize(
        _ raw: Raw,
        durationSec: Int,
        hasDeterministicAudioEvidence: Bool = false
    ) throws -> VideoDiagnosisDraft {
        let highlight = safeText(raw.highlight, hasDeterministicAudioEvidence: hasDeterministicAudioEvidence)
        let focus = safeText(raw.focus, hasDeterministicAudioEvidence: hasDeterministicAudioEvidence)
        let nextAction = safeText(raw.nextAction, hasDeterministicAudioEvidence: hasDeterministicAudioEvidence)
        guard !highlight.isEmpty, !focus.isEmpty, !nextAction.isEmpty else {
            throw VideoDiagnosisDraftError.emptyField
        }
        let duration = max(durationSec, 0)
        var findings: [VideoFinding] = []
        for item in raw.findings ?? [] {
            let title = safeText(item.title, hasDeterministicAudioEvidence: hasDeterministicAudioEvidence)
            let evidence = safeText(item.evidence, hasDeterministicAudioEvidence: hasDeterministicAudioEvidence)
            let cause = safeText(item.cause, hasDeterministicAudioEvidence: hasDeterministicAudioEvidence)
            let action = safeText(item.action, hasDeterministicAudioEvidence: hasDeterministicAudioEvidence)
            guard !title.isEmpty, !evidence.isEmpty, !cause.isEmpty, !action.isEmpty else {
                continue
            }
            guard let start = item.startSec,
                  let end = item.endSec,
                  start >= 0,
                  start < end,
                  end <= duration else { continue }
            findings.append(
                VideoFinding(
                    startSec: start,
                    endSec: end,
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

    private static func clampText(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= 80 ? trimmed : String(trimmed.prefix(80))
    }

    private static func safeText(
        _ value: String?,
        hasDeterministicAudioEvidence: Bool
    ) -> String {
        let text = clampText(value)
        guard !hasDeterministicAudioEvidence, containsUnsupportedPitchPrecision(text) else {
            return text
        }
        return "音高需要进一步确认"
    }

    private static func containsUnsupportedPitchPrecision(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        let patterns = [
            #"(?i)(?<![A-Za-z0-9_])[A-G](?:#|b)?[0-8](?![A-Za-z0-9_])"#,
            #"(?i)\d+(?:\.\d+)?\s*(?:hz|cents?)(?![A-Za-z])"#,
            #"\d+(?:\.\d+)?\s*音分"#,
        ]
        return patterns.contains { pattern in
            (try? NSRegularExpression(pattern: pattern))?.firstMatch(
                in: text, range: range
            ) != nil
        }
    }
}
