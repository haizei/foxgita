import Foundation
import Testing
@testable import foxgita

private struct DiagnosisStubMemoryContext: MemoryContextProviding {
    var text: String
    func block(skill: SkillDefinition, query: String) async -> String { text }
}

private final class GitaMockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storedHandler: (@Sendable (URLRequest) throws -> (Int, Data))?

    static var handler: (@Sendable (URLRequest) throws -> (Int, Data))? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct GitaPracticeExtensionTests {
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
        GitaMockURLProtocol.handler = { _ in (200, response) }
        defer { GitaMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GitaMockURLProtocol.self]
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
        GitaMockURLProtocol.handler = { _ in (200, response) }
        defer { GitaMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GitaMockURLProtocol.self]
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
        GitaMockURLProtocol.handler = { _ in (500, Data()) }
        defer { GitaMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GitaMockURLProtocol.self]
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
        GitaMockURLProtocol.handler = { _ in (200, response) }
        defer { GitaMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GitaMockURLProtocol.self]
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

    @Test func videoDiagnosisRunnerValidatesEvidenceAndRecordsArtifact() async throws {
        let content = """
        {"highlight":"稳定","focus":"节奏","nextAction":"慢练","findings":[
          {"startSec":2,"endSec":8,"title":"节奏","evidence":"拍点落后","cause":"看谱","action":"跟节拍器"},
          {"startSec":10,"endSec":20,"title":"越界","evidence":"画面","cause":"未知","action":"重试"}
        ]}
        """
        let response = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content]]],
            "usage": ["prompt_tokens": 18, "completion_tokens": 9],
        ])
        GitaMockURLProtocol.handler = { _ in (200, response) }
        defer { GitaMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GitaMockURLProtocol.self]
        let log = InvocationLogSpy()
        let runner = VideoDiagnosisRecipeRunner(
            session: URLSession(configuration: config),
            memory: DiagnosisStubMemoryContext(text: "已授权练习偏好"),
            log: log
        )

        let draft = try await runner.generateDiagnosis(
            baseURL: "https://api.openai.com/v1", model: "model", apiKey: "key",
            imageJPEGData: (0..<11).map { Data([$0]) }, contextText: "recording=v1",
            durationSec: 12, invocationId: UUID().uuidString
        )

        #expect(draft.findings.count == 1)
        #expect(draft.findings[0].startSec == 2)
        #expect(log.inputs.first?.skillId == SkillID.diagnoseVideo)
        #expect(log.inputs.first?.usage?.inputTokens == 18)
        #expect(log.inputs.first?.memoryIds == [])
        #expect(log.artifactLinks.count == 1)
    }
}
