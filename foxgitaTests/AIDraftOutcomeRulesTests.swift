import Testing
@testable import foxgita

struct AIDraftOutcomeRulesTests {
    @Test func confirmDetectsEditAndIgnoresEmptySteps() {
        #expect(
            AIDraftOutcomeRules.confirm(
                originalTitle: "F 和弦", originalMinutes: 20, originalSteps: ["热身", "重点"],
                editTitle: "F 和弦", editMinutes: 20, editSteps: ["热身", "重点", "  "]
            ) == .accepted
        )
        #expect(
            AIDraftOutcomeRules.confirm(
                originalTitle: "F 和弦", originalMinutes: 20, originalSteps: ["热身"],
                editTitle: "F 和弦", editMinutes: 15, editSteps: ["热身"]
            ) == .edited
        )
    }
}
