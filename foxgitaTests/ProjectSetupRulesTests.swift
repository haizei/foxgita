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
        #expect(
            ProjectSetupRules.isCreateDirty(
                name: "", goal: "", currentFocus: "", kind: "", stage: ""
            ) == false
        )
        #expect(
            ProjectSetupRules.isCreateDirty(
                name: "  ", goal: "", currentFocus: "", kind: "", stage: ""
            ) == false
        )
        #expect(
            ProjectSetupRules.isCreateDirty(
                name: "知足", goal: "", currentFocus: "", kind: "", stage: ""
            ) == true
        )
        #expect(
            ProjectSetupRules.isCreateDirty(
                name: "", goal: "", currentFocus: "副歌", kind: "", stage: ""
            ) == true
        )
    }

    @Test func editDirtyComparesTrimmedLoaded() {
        #expect(
            ProjectSetupRules.isEditDirty(
                name: "知足", goal: "完整弹唱", currentFocus: "",
                kind: "", stage: "",
                loadedName: "知足", loadedGoal: "完整弹唱", loadedFocus: "",
                loadedKind: "", loadedStage: ""
            ) == false
        )
        #expect(
            ProjectSetupRules.isEditDirty(
                name: "知足 ", goal: "完整弹唱", currentFocus: "副歌",
                kind: "", stage: "",
                loadedName: "知足", loadedGoal: "完整弹唱", loadedFocus: "",
                loadedKind: "", loadedStage: ""
            ) == true
        )
    }

    @Test func knownKindAndStage() {
        #expect(ProjectSetupRules.kinds == ["歌曲", "技巧", "演出准备"])
        #expect(ProjectSetupRules.stages == ["熟悉内容", "分段练习", "串联整首", "稳定演奏", "完成"])
        #expect(ProjectSetupRules.isKnownKind("歌曲") == true)
        #expect(ProjectSetupRules.isKnownKind(" 技巧 ") == true)
        #expect(ProjectSetupRules.isKnownKind("自由") == false)
        #expect(ProjectSetupRules.isKnownKind("") == false)
        #expect(ProjectSetupRules.isKnownStage("串联整首") == true)
        #expect(ProjectSetupRules.isKnownStage("分段") == false)
    }

    @Test func readyStageHiddenWhenBlank() {
        #expect(ProjectSetupRules.showsReadyStage("") == false)
        #expect(ProjectSetupRules.showsReadyStage("   ") == false)
        #expect(ProjectSetupRules.showsReadyStage("串联整首") == true)
        #expect(ProjectSetupRules.showsReadyStage("旧自由文本") == true)
    }

    @Test func createDirtyIncludesKindAndStage() {
        #expect(
            ProjectSetupRules.isCreateDirty(
                name: "", goal: "", currentFocus: "", kind: "", stage: ""
            ) == false
        )
        #expect(
            ProjectSetupRules.isCreateDirty(
                name: "", goal: "", currentFocus: "", kind: "歌曲", stage: ""
            ) == true
        )
        #expect(
            ProjectSetupRules.isCreateDirty(
                name: "", goal: "", currentFocus: "", kind: "", stage: "串联整首"
            ) == true
        )
    }

    @Test func editDirtyIncludesKindAndStage() {
        #expect(
            ProjectSetupRules.isEditDirty(
                name: "知足", goal: "完整弹唱", currentFocus: "",
                kind: "歌曲", stage: "串联整首",
                loadedName: "知足", loadedGoal: "完整弹唱", loadedFocus: "",
                loadedKind: "歌曲", loadedStage: "串联整首"
            ) == false
        )
        #expect(
            ProjectSetupRules.isEditDirty(
                name: "知足", goal: "完整弹唱", currentFocus: "",
                kind: "", stage: "串联整首",
                loadedName: "知足", loadedGoal: "完整弹唱", loadedFocus: "",
                loadedKind: "歌曲", loadedStage: "串联整首"
            ) == true
        )
        #expect(
            ProjectSetupRules.isEditDirty(
                name: "知足", goal: "完整弹唱", currentFocus: "",
                kind: "", stage: "旧自由文本",
                loadedName: "知足", loadedGoal: "完整弹唱", loadedFocus: "",
                loadedKind: "", loadedStage: "旧自由文本"
            ) == false
        )
    }

    @Test func readyFocusHiddenWhenBlank() {
        #expect(ProjectSetupRules.showsReadyFocus("") == false)
        #expect(ProjectSetupRules.showsReadyFocus("   ") == false)
        #expect(ProjectSetupRules.showsReadyFocus("副歌节奏") == true)
        #expect(ProjectSetupRules.hasFocus(" 副歌 ") == true)
    }
}
