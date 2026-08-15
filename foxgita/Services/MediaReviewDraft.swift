import Foundation

enum MediaReviewDraftError: Error, Equatable {
    case emptyField
}

struct MediaReviewDraft: Equatable, Sendable {
    var highlight: String
    var focus: String
    var nextAction: String

    struct Raw: Decodable, Equatable {
        var highlight: String?
        var focus: String?
        var nextAction: String?
    }

    static func normalize(_ raw: Raw) throws -> MediaReviewDraft {
        let highlight = clamp(raw.highlight)
        let focus = clamp(raw.focus)
        let nextAction = clamp(raw.nextAction)
        guard !highlight.isEmpty, !focus.isEmpty, !nextAction.isEmpty else {
            throw MediaReviewDraftError.emptyField
        }
        return MediaReviewDraft(highlight: highlight, focus: focus, nextAction: nextAction)
    }

    private static func clamp(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= 80 ? trimmed : String(trimmed.prefix(80))
    }
}
