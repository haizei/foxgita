import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct MemoryContextTests {
    private func makeLive() throws -> (LiveMemoryContext, SwiftDataMemoryRepository, LocalProfile) {
        let schema = Schema(versionedSchema: GitaSchemaV7.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1", memoryConsent: false)
        context.insert(profile)
        try context.save()
        let repo = SwiftDataMemoryRepository(context: context)
        try repo.upsertDebug(
            MemoryItem(
                profileId: "p1", kind: .goal, key: "goal.current_song",
                summaryText: "当前目标：《晴天》前奏",
                sourceType: "debug_seed", sourceId: "goal.current_song",
                confidence: 1, importance: 1
            )
        )
        try repo.save()
        return (LiveMemoryContext(repository: repo, context: context), repo, profile)
    }

    /// Builtin `planFromImage` still has empty `memoryReadScopes` (Task 6).
    /// Live tests that expect a wrapped block must copy scopes onto the definition.
    private func scopedPlanFromImage() -> SkillDefinition {
        var skill = SkillDefinition.planFromImage
        skill.memoryReadScopes = [.goal, .preference]
        return skill
    }

    @Test func liveReturnsEmptyWhenConsentOffEvenIfMemoriesExist() async throws {
        let (live, _, profile) = try makeLive()
        profile.consent = .disabled
        let text = await live.block(skill: scopedPlanFromImage(), query: "")
        #expect(text == "")
    }

    @Test func liveReturnsEmptyWhenUndecidedEvenIfMemoriesExist() async throws {
        let (live, _, profile) = try makeLive()
        profile.memoryConsent = true
        profile.memoryConsentState = MemoryConsentState.undecided.rawValue
        let text = await live.block(skill: scopedPlanFromImage(), query: "")
        #expect(text == "")
    }

    @Test func liveReturnsWrappedGoalWhenConsentOn() async throws {
        let (live, _, profile) = try makeLive()
        profile.consent = .enabled
        let text = await live.block(skill: scopedPlanFromImage(), query: "")
        #expect(text.contains("<<<BACKGROUND_MEMORY>>>"))
        #expect(text.contains("当前目标：《晴天》前奏"))
        #expect(!text.contains("[ability]"))
    }

    @Test func liveIncludesTaskDerivedGoalWhenConsentEnabled() async throws {
        let (live, repo, profile) = try makeLive()
        profile.consent = .enabled
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "自定义目标")
        try repo.save()
        let text = await live.block(skill: scopedPlanFromImage(), query: "")
        #expect(text.contains("<<<BACKGROUND_MEMORY>>>"))
        #expect(text.contains("自定义目标"))
        #expect(text.contains("[goal]"))
        #expect(!text.contains("你是吉他练习教练。只输出合法 JSON。"))
    }

    @Test func liveIncludesAICandidateAbilityWhenConsentEnabled() async throws {
        let (live, repo, profile) = try makeLive()
        profile.consent = .enabled
        try repo.upsertAICandidate(
            profileId: "p1",
            recordingId: "clip-1",
            summaryText: "压弦要贴品丝",
            valueJSON: "practice.review.media@1.1.0"
        )
        try repo.save()
        let text = await live.block(skill: .reviewMedia, query: "")
        #expect(text.contains("<<<BACKGROUND_MEMORY>>>"))
        #expect(text.contains("压弦要贴品丝"))
        #expect(text.contains("[ability]"))
        #expect(!text.contains("你是吉他练习陪伴教练。根据波形图或练习画面帧给出简短复盘。只返回 JSON，不要 markdown。"))
    }

    @Test func liveIncludesNextSessionGoalAndAbilityWhenConsentEnabled() async throws {
        let (live, repo, profile) = try makeLive()
        profile.consent = .enabled
        try repo.upsertAICandidate(
            profileId: "p1",
            recordingId: "clip-1",
            summaryText: "压弦要贴品丝",
            valueJSON: "practice.review.media@1.1.0"
        )
        try repo.save()
        let text = await live.block(skill: .nextSession, query: "")
        #expect(text.contains("<<<BACKGROUND_MEMORY>>>"))
        #expect(text.contains("当前目标：《晴天》前奏"))
        #expect(text.contains("压弦要贴品丝"))
        #expect(text.contains("[goal]"))
        #expect(text.contains("[ability]"))
        #expect(!text.contains("你是吉他练习教练。只输出合法 JSON。"))
    }
}
