import Foundation
import Testing
@testable import foxgita

struct NextSessionCitationTests {
    private func item(kind: MemoryScope, key: String, summary: String, valueJSON: String = "") -> MemoryItem {
        MemoryItem(
            profileId: "p1", kind: kind, key: key, summaryText: summary,
            valueJSON: valueJSON, sourceType: "user", sourceId: "",
            confidence: 1, importance: 0.8
        )
    }

    @Test func linePrefersFocusThenGoalThenDurationThenGeneric() {
        let focus = item(kind: .ability, key: "ability.current_focus", summary: "压弦要贴品丝")
        let goal = item(kind: .goal, key: "task.custom-1.title", summary: "晴天前奏")
        let pref = item(
            kind: .preference, key: "practice.available_minutes",
            summary: "通常可练 20 分钟", valueJSON: "20"
        )
        #expect(NextSessionCitation.line(items: [focus, goal, pref], selectedMinutes: 20)
            == "已结合你的近期重点：压弦要贴品丝")
        #expect(NextSessionCitation.line(items: [goal, pref], selectedMinutes: 20)
            == "已结合你的目标：晴天前奏")
        #expect(NextSessionCitation.line(items: [pref], selectedMinutes: 20)
            == "已按你的 20 分钟安排")
        #expect(NextSessionCitation.line(items: [], selectedMinutes: 20)
            == "通用建议，还没有可参考的练习记忆")
    }

    @Test func lineTruncatesSummaryTo40Characters() {
        let long = String(repeating: "啊", count: 41)
        let focus = item(kind: .ability, key: "ability.current_focus", summary: long)
        let line = NextSessionCitation.line(items: [focus], selectedMinutes: 20)
        #expect(line == "已结合你的近期重点：\(String(long.prefix(40)))…")
    }

    @Test func resolvedDurationPrefersValidPreference() {
        #expect(NextSessionDuration.resolved(preferenceMinutes: 25, initialMinutes: 10) == 25)
        #expect(NextSessionDuration.resolved(preferenceMinutes: 3, initialMinutes: 10) == 10)
        #expect(NextSessionDuration.resolved(preferenceMinutes: nil, initialMinutes: 10) == 10)
        #expect(NextSessionDuration.resolved(preferenceMinutes: nil, initialMinutes: 1) == 5)
        #expect(NextSessionDuration.parsePreference([
            item(kind: .preference, key: "practice.available_minutes", summary: "x", valueJSON: "30")
        ]) == 30)
        #expect(NextSessionDuration.parsePreference([]) == nil)
    }
}
