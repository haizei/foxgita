import Foundation

enum NextSessionCitation {
    static let durationKey = "practice.available_minutes"
    static let focusKey = "ability.current_focus"

    static func line(items: [MemoryItem], selectedMinutes: Int) -> String {
        if let focus = items.first(where: { $0.key == focusKey }) {
            return "已结合你的近期重点：\(clip(focus.summaryText))"
        }
        if let goal = items.first(where: { $0.kind == .goal }) {
            return "已结合你的目标：\(clip(goal.summaryText))"
        }
        if items.contains(where: { $0.key == durationKey }) {
            return "已按你的 \(selectedMinutes) 分钟安排"
        }
        return "通用建议，还没有可参考的练习记忆"
    }

    private static func clip(_ text: String) -> String {
        if text.count <= 40 { return text }
        return String(text.prefix(40)) + "…"
    }
}

enum NextSessionDuration {
    static func resolved(preferenceMinutes: Int?, initialMinutes: Int) -> Int {
        if let preferenceMinutes, (5...60).contains(preferenceMinutes) {
            return preferenceMinutes
        }
        let clamped = min(60, max(5, initialMinutes))
        return clamped
    }

    static func parsePreference(_ items: [MemoryItem]) -> Int? {
        guard let item = items.first(where: { $0.key == NextSessionCitation.durationKey }) else {
            return nil
        }
        return Int(item.valueJSON)
    }
}
