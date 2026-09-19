import Foundation

enum PracticeTaskOrigin {
    static func stableActiveId(templateId: String) -> String {
        "active-\(templateId)"
    }

    static func photoOriginKey(generationId: String) -> String {
        "ai.photo.\(generationId)"
    }

    static func nextOriginKey(generationId: String) -> String {
        "ai.next.\(generationId)"
    }

    static func aiInvocationID(from originId: String?) -> String? {
        guard let originId else { return nil }
        for prefix in ["ai.photo.", "ai.next."] where originId.hasPrefix(prefix) {
            let id = String(originId.dropFirst(prefix.count))
            return id.isEmpty ? nil : id
        }
        return nil
    }

    static func templateOriginKey(templateId: String) -> String {
        "template.\(templateId)"
    }

    /// "active-tpl-chord-2026-08-19" → templateId "tpl-chord", dayKey "2026-08-19"
    static func parseDailyActiveId(_ id: String) -> (templateId: String, dayKey: String)? {
        guard let match = id.wholeMatch(of: /^active-(.+)-(\d{4}-\d{2}-\d{2})$/) else {
            return nil
        }
        return (String(match.1), String(match.2))
    }
}
