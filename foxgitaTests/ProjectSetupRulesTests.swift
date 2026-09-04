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

    @Test func prepareAcceptsNameOnly() throws {
        let fields = try ProjectSetupRules.prepare(name: " 知足 ", goal: "  ").get()
        #expect(fields.name == "知足")
        #expect(fields.goal == "")
    }

    @Test func prepareKeepsTrimmedGoal() throws {
        let fields = try ProjectSetupRules.prepare(name: "知足", goal: " 完整弹唱 ").get()
        #expect(fields.goal == "完整弹唱")
    }

    @Test func prepareRejectsBlankAndOverlong() {
        #expect(ProjectSetupRules.prepare(name: "  ", goal: "目标") == .failure(.nameEmpty))
        #expect(
            ProjectSetupRules.prepare(name: String(repeating: "啊", count: 41), goal: "")
                == .failure(.nameTooLong)
        )
        #expect(
            ProjectSetupRules.prepare(name: "知足", goal: String(repeating: "啊", count: 121))
                == .failure(.goalTooLong)
        )
    }

    @Test func errorFieldAndReason() {
        #expect(ProjectSetupError.nameEmpty.fieldName == "name")
        #expect(ProjectSetupError.nameEmpty.reason == "empty")
        #expect(ProjectSetupError.goalTooLong.fieldName == "goal")
        #expect(ProjectSetupError.goalTooLong.reason == "too_long")
    }

    @Test func createDirtyOnlyNameAndGoal() {
        #expect(ProjectSetupRules.isCreateDirty(name: "", goal: "") == false)
        #expect(ProjectSetupRules.isCreateDirty(name: "  ", goal: "") == false)
        #expect(ProjectSetupRules.isCreateDirty(name: "知足", goal: "") == true)
        #expect(ProjectSetupRules.isCreateDirty(name: "", goal: "完整弹唱") == true)
    }

    @Test func editDirtyComparesTrimmedLoaded() {
        #expect(
            ProjectSetupRules.isEditDirty(
                name: "知足", goal: "完整弹唱",
                loadedName: "知足", loadedGoal: "完整弹唱"
            ) == false
        )
        #expect(
            ProjectSetupRules.isEditDirty(
                name: "知足 ", goal: "完整弹唱",
                loadedName: "知足", loadedGoal: ""
            ) == true
        )
    }

    @Test func fromPracticeDirtyIgnoresUnchangedPrefill() {
        #expect(ProjectSetupRules.isFromPracticeDirty(name: "《知足》主歌", initialName: "《知足》主歌") == false)
        #expect(ProjectSetupRules.isFromPracticeDirty(name: "学会《知足》", initialName: "《知足》主歌") == true)
        #expect(ProjectSetupRules.isFromPracticeDirty(name: "  ", initialName: "《知足》主歌") == true)
    }

    @Test func hasGoal() {
        #expect(ProjectSetupRules.hasGoal("") == false)
        #expect(ProjectSetupRules.hasGoal("  ") == false)
        #expect(ProjectSetupRules.hasGoal("完整弹唱") == true)
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
}
