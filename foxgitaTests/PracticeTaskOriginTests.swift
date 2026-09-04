import Testing
@testable import foxgita

struct PracticeTaskOriginTests {
    @Test func stableActiveIdAndDailyParse() {
        #expect(PracticeTaskOrigin.stableActiveId(templateId: "tpl-chord") == "active-tpl-chord")
        let parsed = PracticeTaskOrigin.parseDailyActiveId("active-tpl-chord-2026-08-19")
        #expect(parsed?.templateId == "tpl-chord")
        #expect(parsed?.dayKey == "2026-08-19")
        #expect(PracticeTaskOrigin.parseDailyActiveId("active-tpl-chord") == nil)
        #expect(PracticeTaskOrigin.photoOriginKey(generationId: "g1") == "ai.photo.g1")
        #expect(PracticeTaskOrigin.nextOriginKey(generationId: "g1") == "ai.next.g1")
        #expect(PracticeTaskOrigin.templateOriginKey(templateId: "tpl-chord") == "template.tpl-chord")
    }
}
