import Foundation
import Testing
@testable import foxgita

@Suite(.serialized)
struct GitaPracticeExtensionTests {
    @Test func migrationResolverSelectsExactlyOnePathPerRecipe() {
        let suite = "gita.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "ai.recipe.migration.\(SkillID.nextSession)"
        defaults.set(RecipeMigrationState.legacy.rawValue, forKey: key)
        #expect(!RecipeMigrationResolver(defaults: defaults).usesPlatform(for: SkillID.nextSession))
        defaults.set(RecipeMigrationState.internalPlatform.rawValue, forKey: key)
        #expect(RecipeMigrationResolver(defaults: defaults).usesPlatform(for: SkillID.nextSession))
    }

    @Test @MainActor func approvalBindsEditedDraftAndCannotReplay() async throws {
        let gate = PracticeDraftApprovalGate(secret: Data("test-secret".utf8))
        let original = AIPracticeDraft(
            title: "原稿", category: .chord, targetMin: 10, steps: ["C-G"], chords: ["C", "G"]
        )
        var edited = original
        edited.title = "编辑稿"
        let token = gate.issue(draft: original, userID: "u", sessionID: "s", draftID: "d")

        await #expect(throws: GateRefusal.approvalMismatch) {
            try await gate.validate(token, draft: edited, userID: "u", sessionID: "s", draftID: "d")
        }
        let accepted = gate.issue(draft: edited, userID: "u", sessionID: "s", draftID: "d")
        try await gate.validate(accepted, draft: edited, userID: "u", sessionID: "s", draftID: "d")
        await #expect(throws: GateRefusal.approvalReplayed) {
            try await gate.validate(accepted, draft: edited, userID: "u", sessionID: "s", draftID: "d")
        }
    }

    @Test func declaresExactlyTheFourPhaseOneRecipesFromSkillRegistry() {
        let recipes = GitaPracticeExtension().recipes
        #expect(Set(recipes.map(\.id)) == [
            SkillID.nextSession,
            SkillID.planFromImage,
            SkillID.reviewMedia,
            SkillID.diagnoseVideo,
        ])
        #expect(recipes.count == 4)
        #expect(recipes.first { $0.id == SkillID.nextSession }?.version == SkillDefinition.nextSession.version)
        #expect(recipes.first { $0.id == SkillID.nextSession }?.approvalPolicy == .hostRequired)
        #expect(recipes.first { $0.id == SkillID.reviewMedia }?.approvalPolicy == ApprovalPolicy.none)
    }

    @Test func nextSessionRunnerPreservesBudgetNormalizationAndRecordsArtifactChain() async throws {
        let rawContent = """
        {"title":"  今日和弦  ","category":"chord","targetMin":40,
         "steps":["热身","换和弦","超时"],"stepMinutes":[5,10,20],"chords":["C","G"]}
        """
        let response = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": rawContent]]],
            "usage": ["prompt_tokens": 21, "completion_tokens": 8],
        ])
        TransportMockURLProtocol.handler = { _ in (200, response) }
        defer { TransportMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransportMockURLProtocol.self]
        let log = InvocationLogSpy()
        let invocationID = UUID().uuidString
        let runner = NextSessionRecipeRunner(
            session: URLSession(configuration: config),
            log: log
        )

        let draft = try await runner.generateDraft(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "test-key",
            budgetMinutes: 20,
            fallbackCategory: .song,
            invocationId: invocationID
        )

        #expect(draft.title == "今日和弦")
        #expect(draft.targetMin == 20)
        #expect(draft.steps == ["热身 · 5 分钟", "换和弦 · 10 分钟"])
        #expect(log.inputs.count == 1)
        #expect(log.inputs.first?.runtime == RuntimeKind.messages.rawValue)
        #expect(log.inputs.first?.executionState == .presenting)
        #expect(log.inputs.first?.usage?.inputTokens == 21)
        #expect(log.artifactLinks.count == 1)
        #expect(log.artifactLinks.first?.invocationID == invocationID)
    }

    @Test func imageRunnerUsesSharedValidatorAndKeepsBytesOutOfPrompt() async throws {
        let rawContent = #"{"title":"图片练习","category":"song","targetMin":15,"steps":["慢练"]}"#
        let response = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": rawContent]]],
        ])
        let marker = Data("private-image-marker".utf8)
        TransportMockURLProtocol.handler = { _ in (200, response) }
        defer { TransportMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransportMockURLProtocol.self]
        let log = InvocationLogSpy()
        let invocationID = UUID()
        let runner = ImagePlanRecipeRunner(session: URLSession(configuration: config), log: log)

        let draft = try await runner.runImagePlan(
            imageJPEGData: [marker],
            fallbackCategory: .left,
            credentials: RuntimeCredentials(baseURL: "https://api.openai.com/v1", apiKey: "key", model: "model"),
            invocationID: invocationID
        )

        #expect(draft.title == "图片练习")
        #expect(log.inputs.first?.skillId == SkillID.planFromImage)
        #expect(log.inputs.first?.memoryIds == [])
        #expect(log.artifactLinks.count == 1)
    }

    @Test func imageRunnerFailureRecordsFailedOutcome() async {
        TransportMockURLProtocol.handler = { _ in (500, Data()) }
        defer { TransportMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransportMockURLProtocol.self]
        let log = InvocationLogSpy()
        let runner = ImagePlanRecipeRunner(session: URLSession(configuration: config), log: log)

        await #expect(throws: VisionPracticeError.httpStatus(500)) {
            try await runner.runImagePlan(
                imageJPEGData: [Data([1])],
                fallbackCategory: .left,
                credentials: RuntimeCredentials(baseURL: "https://api.openai.com/v1", apiKey: "key", model: "model"),
                invocationID: UUID()
            )
        }
        #expect(log.inputs.first?.draftOutcome == .failed)
        #expect(log.inputs.first?.executionState == .failed)
        #expect(log.artifactLinks.isEmpty)
    }

    @Test func mediaReviewRunnerRecordsArtifactAndScopedProvenance() async throws {
        let content = #"{"highlight":"稳","focus":"换弦","nextAction":"慢练"}"#
        let response = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content]]],
            "usage": ["prompt_tokens": 12, "completion_tokens": 6],
        ])
        TransportMockURLProtocol.handler = { _ in (200, response) }
        defer { TransportMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransportMockURLProtocol.self]
        let log = InvocationLogSpy()
        let invocationID = UUID().uuidString
        let runner = MediaReviewRecipeRunner(session: URLSession(configuration: config), log: log)

        let draft = try await runner.generateReview(
            baseURL: "https://api.openai.com/v1", model: "model", apiKey: "key",
            imageJPEGData: [Data([1])], contextText: "recording=r1\nduration=12",
            invocationId: invocationID
        )

        #expect(draft.focus == "换弦")
        #expect(log.inputs.first?.id == invocationID)
        #expect(log.inputs.first?.executionState == .presenting)
        #expect(log.inputs.first?.usage?.inputTokens == 12)
        #expect(log.artifactLinks.count == 1)
    }
}
