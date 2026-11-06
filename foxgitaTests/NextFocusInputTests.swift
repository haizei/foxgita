import Foundation
import Testing
@testable import foxgita

@MainActor
private final class FocusInputPersistence: NextFocusPersisting {
    var files: [UUID: Data] = [:]
    func read(profileID: UUID) throws -> Data? { files[profileID] }
    func write(_ data: Data, profileID: UUID) throws { files[profileID] = data }
    func removeAll() throws { files.removeAll() }
}

@MainActor
private final class CancelledFocusGenerator: NextFocusGenerating {
    var started = false
    var finished = false
    func generate(context: NextFocusContext, supplement: String, baseURL: String,
                  model: String, apiKey: String) async throws -> NextFocusOutput {
        started = true
        defer { finished = true }
        do { try await Task.sleep(for: .seconds(10)) }
        catch { throw URLError(.cancelled) }
        throw URLError(.timedOut)
    }
}

@MainActor
struct NextFocusInputTests {
    private func context() -> NextFocusContext {
        .init(profileID: UUID(), sourceID: UUID(), sourceDay: "2026-11-06",
              title: "和弦转换", categoryRaw: "chord")
    }

    @Test func supplementRemainsADraftUntilGeneratedAndConfirmed() throws {
        let disk = FocusInputPersistence(), c = context()
        let store = NextFocusStore(persistence: disk)
        let first = try store.beginGeneration(c)
        try store.applyGenerated(.init(recap: "练习记录已保存。", focus: "", basis: "请补充具体内容"), ticket: first)
        try store.editSupplement(profileID: c.profileID, sourceID: c.sourceID, text: "下次继续 C→G")
        let reopened = NextFocusStore(persistence: disk)
        let draft = try #require(reopened.document(c.profileID).drafts[c.sourceID.uuidString])
        #expect(draft.supplement == "下次继续 C→G")
        #expect(draft.requiresSupplement == true)
        #expect(throws: NextFocusError.emptyFocus) { try reopened.confirm(profileID: c.profileID, sourceID: c.sourceID) }
        let ticket = try reopened.beginGeneration(c)
        try reopened.applyGenerated(.init(recap: "练习记录已保存。", focus: "继续练习 C→G。", basis: "你补充的下次安排"), ticket: ticket)
        #expect(try reopened.document(c.profileID).action == nil)
        let confirmed = try reopened.confirm(profileID: c.profileID, sourceID: c.sourceID)
        #expect(confirmed.text == "继续练习 C→G。")
    }

    @Test func manualFallbackReopensAsAnEditableFocus() throws {
        let disk = FocusInputPersistence(), c = context()
        let store = NextFocusStore(persistence: disk)
        let ticket = try store.beginGeneration(c)
        try store.applyGenerated(.init(recap: "本次练习已保存。", focus: "", basis: "信息不足"), ticket: ticket)
        try store.edit(profileID: c.profileID, sourceID: c.sourceID, text: "继续 C→G，留意停顿。")
        _ = try store.confirm(profileID: c.profileID, sourceID: c.sourceID)
        let draft = try #require(NextFocusStore(persistence: disk).document(c.profileID).drafts[c.sourceID.uuidString])
        #expect(draft.requiresSupplement == false)
        #expect(draft.text == "继续 C→G，留意停顿。")
    }

    @Test func lateResultCannotReplaceNewSupplementInput() throws {
        let store = NextFocusStore(persistence: FocusInputPersistence()), c = context()
        let ticket = try store.beginGeneration(c)
        try store.editSupplement(profileID: c.profileID, sourceID: c.sourceID, text: "我改为练主歌")
        try store.applyGenerated(.init(recap: "旧总结", focus: "旧安排", basis: "旧依据"), ticket: ticket)
        let draft = try #require(store.document(c.profileID).drafts[c.sourceID.uuidString])
        #expect(draft.supplement == "我改为练主歌")
        #expect(draft.text.isEmpty)
        #expect(try store.document(c.profileID).action == nil)
    }

    @Test func uncheckingProjectUpdateClearsAnEarlierPendingUpdate() throws {
        let store = NextFocusStore(persistence: FocusInputPersistence())
        var c = context()
        c.projectID = UUID()
        c.projectFocus = "旧项目重点"
        _ = try store.prepare(c)
        try store.edit(profileID: c.profileID, sourceID: c.sourceID, text: "继续 C→G")
        _ = try store.confirm(profileID: c.profileID, sourceID: c.sourceID, updateProject: true)
        _ = try store.confirm(profileID: c.profileID, sourceID: c.sourceID, updateProject: false)
        #expect(try store.document(c.profileID).drafts[c.sourceID.uuidString]?.pendingProjectUpdate == nil)
        #expect(try store.document(c.profileID).action?.text == "继续 C→G")
    }

    @Test func editingCancelsTransportWithoutWritingASpuriousFailure() async throws {
        let store = NextFocusStore(persistence: FocusInputPersistence()), c = context()
        let generator = CancelledFocusGenerator()
        try store.generate(c, baseURL: "https://example.invalid", model: "test", apiKey: "test", client: generator)
        for _ in 0..<200 {
            if generator.started { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(generator.started)
        try store.edit(profileID: c.profileID, sourceID: c.sourceID, text: "我自己的下次重点")
        for _ in 0..<200 {
            if generator.finished { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(generator.finished)
        let draft = try #require(store.document(c.profileID).drafts[c.sourceID.uuidString])
        #expect(draft.text == "我自己的下次重点")
        #expect(draft.generationError == nil)
    }
}
