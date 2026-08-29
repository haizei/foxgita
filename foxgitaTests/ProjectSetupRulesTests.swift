import Foundation
import Testing
@testable import foxgita

struct ProjectSetupRulesTests {
    @Test func trimmedStripsEnds() {
        #expect(ProjectSetupRules.trimmed("  知足  ") == "知足")
        #expect(ProjectSetupRules.trimmed("   ") == "")
    }

    @Test func clampCutsAtMax() {
        let fortyOne = String(repeating: "啊", count: 41)
        #expect(ProjectSetupRules.clamp(fortyOne, max: ProjectSetupRules.nameMax).count == 40)
    }

    @Test func prepareAcceptsNameAndGoalOnly() throws {
        let fields = try ProjectSetupRules.prepare(
            name: " 知足 ",
            goal: " 完整弹唱 ",
            currentFocus: "  "
        ).get()
        #expect(fields.name == "知足")
        #expect(fields.goal == "完整弹唱")
        #expect(fields.currentFocus == "")
    }

    @Test func prepareRejectsBlankAndOverlong() {
        #expect(ProjectSetupRules.prepare(name: "  ", goal: "目标", currentFocus: "") == .failure(.nameEmpty))
        #expect(ProjectSetupRules.prepare(name: "知足", goal: "  ", currentFocus: "") == .failure(.goalEmpty))
        #expect(
            ProjectSetupRules.prepare(
                name: String(repeating: "啊", count: 41),
                goal: "目标",
                currentFocus: ""
            ) == .failure(.nameTooLong)
        )
        #expect(
            ProjectSetupRules.prepare(
                name: "知足",
                goal: String(repeating: "啊", count: 121),
                currentFocus: ""
            ) == .failure(.goalTooLong)
        )
        #expect(
            ProjectSetupRules.prepare(
                name: "知足",
                goal: "目标",
                currentFocus: String(repeating: "啊", count: 121)
            ) == .failure(.focusTooLong)
        )
    }

    @Test func errorFieldAndReason() {
        #expect(ProjectSetupError.nameEmpty.fieldName == "name")
        #expect(ProjectSetupError.nameEmpty.reason == "empty")
        #expect(ProjectSetupError.goalTooLong.fieldName == "goal")
        #expect(ProjectSetupError.goalTooLong.reason == "too_long")
        #expect(ProjectSetupError.focusTooLong.fieldName == "currentFocus")
    }

    @Test func createDirtyIgnoresWhitespaceOnly() {
        #expect(ProjectSetupRules.isCreateDirty(name: "", goal: "", currentFocus: "") == false)
        #expect(ProjectSetupRules.isCreateDirty(name: "  ", goal: "", currentFocus: "") == false)
        #expect(ProjectSetupRules.isCreateDirty(name: "知足", goal: "", currentFocus: "") == true)
        #expect(ProjectSetupRules.isCreateDirty(name: "", goal: "", currentFocus: "副歌") == true)
    }

    @Test func editDirtyComparesTrimmedLoaded() {
        #expect(
            ProjectSetupRules.isEditDirty(
                name: "知足", goal: "完整弹唱", currentFocus: "",
                loadedName: "知足", loadedGoal: "完整弹唱", loadedFocus: ""
            ) == false
        )
        #expect(
            ProjectSetupRules.isEditDirty(
                name: "知足 ", goal: "完整弹唱", currentFocus: "副歌",
                loadedName: "知足", loadedGoal: "完整弹唱", loadedFocus: ""
            ) == true
        )
    }

    @Test func readyFocusHiddenWhenBlank() {
        #expect(ProjectSetupRules.showsReadyFocus("") == false)
        #expect(ProjectSetupRules.showsReadyFocus("   ") == false)
        #expect(ProjectSetupRules.showsReadyFocus("副歌节奏") == true)
        #expect(ProjectSetupRules.hasFocus(" 副歌 ") == true)
    }
}
