import Foundation
import Testing
@testable import foxgita

@MainActor
private final class FocusTestPersistence: NextFocusPersisting {
    var files: [UUID: Data] = [:]
    var failWrites = false
    func read(profileID: UUID) throws -> Data? { files[profileID] }
    func write(_ data: Data, profileID: UUID) throws {
        if failWrites { throw CocoaError(.fileWriteOutOfSpace) }
        files[profileID] = data
    }
    func removeAll() throws { files.removeAll() }
}

private struct FailingFocusGenerator: NextFocusGenerating {
    func generate(context: NextFocusContext, supplement: String, baseURL: String,
                  model: String, apiKey: String) async throws -> NextFocusOutput {
        throw URLError(.timedOut)
    }
}

@MainActor
struct NextFocusStoreTests {
    private func context(profile: UUID = UUID(), source: UUID = UUID()) -> NextFocusContext {
        NextFocusContext(profileID: profile, sourceID: source, sourceDay: "2026-11-06",
                         title: "和弦转换", categoryRaw: "chord", steps: ["C→G"], note: "换到 G 时有停顿")
    }

    @Test func noActionUntilExplicitConfirmationAndSurvivesReload() throws {
        let disk = FocusTestPersistence(), store = NextFocusStore(persistence: FocusTestPersistence())
        let c = context()
        _ = try store.prepare(c)
        #expect(try store.document(c.profileID).action == nil)
        let persisted = NextFocusStore(persistence: disk)
        _ = try persisted.prepare(c)
        try persisted.edit(profileID: c.profileID, sourceID: c.sourceID, text: "继续 C→G")
        let action = try persisted.confirm(profileID: c.profileID, sourceID: c.sourceID)
        #expect(action.text == "继续 C→G")
        #expect(try NextFocusStore(persistence: disk).document(c.profileID).action?.id == action.id)
    }

    @Test func whitespaceCannotBecomeAnAction() throws {
        let store = NextFocusStore(persistence: FocusTestPersistence()), c = context()
        _ = try store.prepare(c)
        try store.edit(profileID: c.profileID, sourceID: c.sourceID, text: " \n ")
        #expect(throws: NextFocusError.emptyFocus) {
            try store.confirm(profileID: c.profileID, sourceID: c.sourceID)
        }
    }

    @Test func replacementRequiresExplicitChoiceAndWriteFailureProtectsOldAction() throws {
        let disk = FocusTestPersistence(), profile = UUID()
        let store = NextFocusStore(persistence: disk)
        let first = context(profile: profile), second = context(profile: profile)
        _ = try store.prepare(first)
        try store.edit(profileID: profile, sourceID: first.sourceID, text: "旧重点")
        let old = try store.confirm(profileID: profile, sourceID: first.sourceID)
        _ = try store.prepare(second)
        try store.edit(profileID: profile, sourceID: second.sourceID, text: "新重点")
        #expect(throws: NextFocusError.replacementRequired) {
            try store.confirm(profileID: profile, sourceID: second.sourceID)
        }
        disk.failWrites = true
        #expect(throws: (any Error).self) {
            try store.confirm(profileID: profile, sourceID: second.sourceID, replace: true)
        }
        #expect(try store.document(profile).action?.id == old.id)
        #expect(try store.document(profile).drafts[second.sourceID.uuidString]?.text == "新重点")
    }

    @Test func lateGenerationNeverOverwritesEditingOrANewerRequest() throws {
        let store = NextFocusStore(persistence: FocusTestPersistence()), c = context()
        let old = try store.beginGeneration(c)
        try store.edit(profileID: c.profileID, sourceID: c.sourceID, text: "用户自己的安排")
        try store.applyGenerated(.init(recap: "练习了 C→G", focus: "过时结果", basis: "本次记录"), ticket: old)
        #expect(try store.document(c.profileID).drafts[c.sourceID.uuidString]?.text == "用户自己的安排")
        let first = try store.beginGeneration(c), second = try store.beginGeneration(c)
        try store.applyGenerated(.init(recap: "练习了 C→G", focus: "旧请求", basis: "本次记录"), ticket: first)
        try store.applyGenerated(.init(recap: "练习了 C→G", focus: "新请求", basis: "本次记录"), ticket: second)
        #expect(try store.document(c.profileID).drafts[c.sourceID.uuidString]?.text == "新请求")
    }

    @Test func skipHasNaturalDayScopeAndDoesNotCompleteAction() throws {
        let store = NextFocusStore(persistence: FocusTestPersistence()), c = context()
        _ = try store.prepare(c)
        try store.edit(profileID: c.profileID, sourceID: c.sourceID, text: "继续 C→G")
        _ = try store.confirm(profileID: c.profileID, sourceID: c.sourceID)
        try store.skip(profileID: c.profileID, day: "2026-11-06")
        #expect(try store.visibleAction(profileID: c.profileID, day: "2026-11-06") == nil)
        #expect(try store.visibleAction(profileID: c.profileID, day: "2026-11-07") != nil)
        try store.skip(profileID: c.profileID, day: nil)
        #expect(try store.visibleAction(profileID: c.profileID, day: "2026-11-06") != nil)
    }

    @Test func profileIsolationAndCorruptStorageCannotBeOverwritten() throws {
        let disk = FocusTestPersistence(), store = NextFocusStore(persistence: FocusTestPersistence())
        let c = context()
        _ = try store.prepare(c)
        try store.edit(profileID: c.profileID, sourceID: c.sourceID, text: "重点")
        _ = try store.confirm(profileID: c.profileID, sourceID: c.sourceID)
        #expect(try store.document(UUID()).action == nil)
        disk.files[c.profileID] = Data("corrupt".utf8)
        let broken = NextFocusStore(persistence: disk)
        #expect(throws: (any Error).self) { try broken.prepare(c) }
        #expect(disk.files[c.profileID] == Data("corrupt".utf8))
    }

    @Test func outputMustContainASummaryButMayRequestMoreInformation() throws {
        let insufficient = try NextFocusOutput.parse(#"{"recap":"练习了 C→G","focus":"","basis":"需要补充"}"#)
        #expect(insufficient.focus.isEmpty)
        #expect(throws: (any Error).self) { try NextFocusOutput.parse(#"{"focus":"继续"}"#) }
    }

    @Test func failedRegenerationKeepsOriginalEvidenceAndStaleWarning() throws {
        let disk = FocusTestPersistence(), store = NextFocusStore(persistence: FocusTestPersistence())
        let c = context()
        let ticket = try store.beginGeneration(c)
        try store.applyGenerated(.init(recap: "原总结", focus: "原重点", basis: "原依据"), ticket: ticket)
        var changed = c
        changed.projectFocus = "新项目重点"
        _ = try store.beginGeneration(changed)
        #expect(try store.document(c.profileID).drafts[c.sourceID.uuidString]?.context == c)
        let reloadable = NextFocusStore(persistence: disk)
        _ = try reloadable.prepare(c)
        _ = try reloadable.beginGeneration(changed)
        let reloaded = try NextFocusStore(persistence: disk).document(c.profileID)
        #expect(reloaded.drafts[c.sourceID.uuidString]?.context == c)
    }

    @Test func reconfirmingConsumedDraftStartsANewActionLifecycle() throws {
        let store = NextFocusStore(persistence: FocusTestPersistence()), c = context()
        _ = try store.prepare(c)
        try store.edit(profileID: c.profileID, sourceID: c.sourceID, text: "重点")
        let first = try store.confirm(profileID: c.profileID, sourceID: c.sourceID)
        let retry = try store.confirm(profileID: c.profileID, sourceID: c.sourceID)
        #expect(first.id == retry.id)
        try store.complete(profileID: c.profileID, itemID: UUID(), originID: first.originID)
        let second = try store.confirm(profileID: c.profileID, sourceID: c.sourceID)
        #expect(first.id != second.id)
        #expect(try store.confirm(profileID: c.profileID, sourceID: c.sourceID).id == second.id)
    }

    @Test func replacedActionAlsoEndsItsDraftLifecycle() throws {
        let store = NextFocusStore(persistence: FocusTestPersistence()), profile = UUID()
        let a = context(profile: profile), b = context(profile: profile)
        for c in [a, b] {
            _ = try store.prepare(c)
            try store.edit(profileID: profile, sourceID: c.sourceID, text: "重点")
        }
        let first = try store.confirm(profileID: profile, sourceID: a.sourceID)
        _ = try store.confirm(profileID: profile, sourceID: b.sourceID, replace: true)
        try store.complete(profileID: profile, itemID: UUID(), originID: first.originID)
        let revived = try store.confirm(profileID: profile, sourceID: a.sourceID, replace: true)
        #expect(revived.id != first.id)
    }

    @Test func skipUndoIsAvailableAfterReload() throws {
        let disk = FocusTestPersistence(), c = context()
        let store = NextFocusStore(persistence: disk)
        _ = try store.prepare(c)
        try store.edit(profileID: c.profileID, sourceID: c.sourceID, text: "重点")
        _ = try store.confirm(profileID: c.profileID, sourceID: c.sourceID)
        try store.skip(profileID: c.profileID, day: "2026-11-06")
        let reloaded = NextFocusStore(persistence: disk)
        #expect(try reloaded.document(c.profileID).action?.skippedDay == "2026-11-06")
        try reloaded.skip(profileID: c.profileID, day: nil)
        #expect(try reloaded.visibleAction(profileID: c.profileID, day: "2026-11-06") != nil)
    }

    @Test func onlyExplicitEvidenceIsSentToAI() throws {
        let c = context()
        let prompt = try NextFocusClient.userText(context: c, supplement: "下次练主歌")
        let data = try #require(prompt.data(using: .utf8))
        let value = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(value["userNextIntention"] as? String == "下次练主歌")
        #expect(value["note"] as? String == c.note)
        #expect(value["actualSeconds"] == nil)
        #expect(!prompt.contains(c.profileID.uuidString))
        #expect(!prompt.contains(c.sourceID.uuidString))
        #expect(value["memory"] == nil)
        #expect(SkillRegistry.builtin.skill(id: SkillID.nextFocus)?.memoryReadScopes == [])
        #expect(SkillRegistry.builtin.skill(id: SkillID.nextFocus)?.memoryWritePolicy == .deny)
    }

    @Test func generationPersistenceFailureDoesNotHideTheExistingAction() async throws {
        let disk = FocusTestPersistence(), c = context()
        let store = NextFocusStore(persistence: disk)
        _ = try store.prepare(c)
        try store.edit(profileID: c.profileID, sourceID: c.sourceID, text: "用户重点")
        let action = try store.confirm(profileID: c.profileID, sourceID: c.sourceID)
        try store.generate(c, baseURL: "https://example.invalid", model: "test", apiKey: "test",
                           client: FailingFocusGenerator())
        disk.failWrites = true
        for _ in 0..<200 {
            if !store.isGenerating(c) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!store.isGenerating(c))
        #expect(store.readErrors[c.profileID] == nil)
        #expect(store.generationError(c) != nil)
        disk.failWrites = false
        #expect(try store.document(c.profileID).action?.id == action.id)
    }

    @Test func failedSupplementSaveInvalidatesOutstandingGeneration() throws {
        let disk = FocusTestPersistence(), c = context()
        let store = NextFocusStore(persistence: disk)
        let initial = try store.beginGeneration(c)
        try store.applyGenerated(.init(recap: "练习内容不足", focus: "", basis: "请补充"), ticket: initial)
        let pending = try store.beginGeneration(c)
        disk.failWrites = true
        #expect(throws: (any Error).self) {
            try store.editSupplement(profileID: c.profileID, sourceID: c.sourceID, text: "下次练主歌")
        }
        disk.failWrites = false
        try store.applyGenerated(.init(recap: "旧请求", focus: "继续前奏", basis: "旧依据"), ticket: pending)
        let draft = try #require(try store.document(c.profileID).drafts[c.sourceID.uuidString])
        #expect(draft.requiresSupplement == true)
        #expect(draft.text.isEmpty)
    }

    @Test func projectRetryDoesNotReviveCompletedActionOrReplaceAnotherAction() throws {
        let (store, _) = integratedStore(FocusTestPersistence())
        let project = try store.createProject(name: "晴天", goal: "前奏", now: .now)
        let source = try seedSource(store, projectID: project.id)
        let completed = try confirm(store, source: source, project: true)
        try store.suggestions.complete(profileID: source.profileId, itemID: UUID(), originID: completed.originID)
        let nextSource = try seedSource(store)
        let current = try confirm(store, source: nextSource)
        try store.suggestions.editProjectUpdate(profileID: source.profileId, sourceID: source.id, text: "项目改为练主歌")
        try store.applyNextFocusProjectUpdate(profileID: source.profileId, sourceID: source.id)
        #expect(project.currentFocus == "项目改为练主歌")
        #expect(try store.suggestions.document(source.profileId).action?.id == current.id)
        #expect(try store.suggestions.document(source.profileId).drafts[source.id.uuidString]?.consumed == true)
    }

    private func integratedStore(_ disk: FocusTestPersistence) -> (PracticeStore, InMemoryPracticeRepository) {
        let repo = InMemoryPracticeRepository()
        let defaults = UserDefaults(suiteName: "next-focus-tests.\(UUID())")!
        let store = PracticeStore(repository: repo, defaults: defaults, suggestions: NextFocusStore(persistence: disk))
        store.prepare()
        return (store, repo)
    }

    private func seedSource(_ store: PracticeStore, projectID: UUID? = nil) throws -> PracticeItem {
        try store.createPracticeItem(input: .init(title: "和弦转换", category: .chord, source: .custom,
            originId: nil, bpm: 80, timeSignature: "4/4", steps: ["C→G"], projectId: projectID),
            now: .now, calendar: .current)
    }

    private func confirm(_ store: PracticeStore, source: PracticeItem, project: Bool = false) throws -> NextFocusAction {
        _ = try store.suggestions.prepare(store.nextFocusContext(itemID: source.id))
        try store.suggestions.edit(profileID: source.profileId, sourceID: source.id, text: "继续 C→G，留意停顿")
        return try store.suggestions.confirm(profileID: source.profileId, sourceID: source.id, updateProject: project)
    }

    @Test func partialAssociationRetryAndNextDayNeverDuplicateOrMoveTime() throws {
        let disk = FocusTestPersistence()
        let (store, repo) = integratedStore(disk)
        let source = try seedSource(store)
        let action = try confirm(store, source: source)
        disk.failWrites = true
        #expect(throws: (any Error).self) {
            try store.openSuggestedPractice(actionID: action.id, completedIDs: [])
        }
        #expect(repo.storedPracticeItems.count == 2)
        disk.failWrites = false
        let reopened = PracticeStore(repository: repo, suggestions: NextFocusStore(persistence: disk))
        let first = try reopened.openSuggestedPractice(actionID: action.id, completedIDs: [])
        #expect(repo.storedPracticeItems.count == 2)
        #expect(first.durationSeconds == 0)
        let retry = try reopened.openSuggestedPractice(actionID: action.id, completedIDs: [])
        #expect(retry.id == first.id)
        try reopened.savePracticeItem(id: first.id, durationSeconds: 73, note: "保留事实", now: .now)
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let next = try reopened.openSuggestedPractice(actionID: action.id, completedIDs: [], now: tomorrow)
        #expect(next.id != first.id)
        #expect(next.durationSeconds == 0)
        #expect(first.durationSeconds == 73)
        #expect(first.practiceDayKey != next.practiceDayKey)
        try reopened.completeSuggestedPractice(item: next)
        #expect(try reopened.suggestions.document(source.profileId).action == nil)
        let durable = try NextFocusStore(persistence: disk).document(source.profileId)
        #expect(durable.completedExecutionIDs?.contains(next.id) == true)
    }

    @Test func unavailableSourceNeedsExplicitFreePracticeChoice() throws {
        let (store, repo) = integratedStore(FocusTestPersistence())
        let source = try seedSource(store), action = try confirm(store, source: source)
        repo.removePracticeItem(id: source.id)
        #expect(throws: (any Error).self) { try store.openSuggestedPractice(actionID: action.id, completedIDs: []) }
        let free = try store.openSuggestedPractice(actionID: action.id, completedIDs: [], allowFreePractice: true)
        #expect(free.projectId == nil)
        #expect(free.durationSeconds == 0)
        #expect(free.subtitle == action.text)
    }

    @Test func projectConflictAndFailurePreserveConfirmedAction() throws {
        let (store, repo) = integratedStore(FocusTestPersistence())
        let project = try store.createProject(name: "晴天", goal: "前奏", now: .now)
        try store.updateProjectFocus(id: project.id, currentFocus: "旧重点", now: .now)
        let source = try seedSource(store, projectID: project.id)
        let action = try confirm(store, source: source, project: true)
        try store.updateProjectFocus(id: project.id, currentFocus: "别人修改的重点", now: .now)
        #expect(throws: (any Error).self) { try store.applyNextFocusProjectUpdate(profileID: source.profileId, sourceID: source.id) }
        #expect(try store.suggestions.document(source.profileId).action?.id == action.id)
        #expect(throws: (any Error).self) {
            try store.applyNextFocusProjectUpdate(profileID: source.profileId, sourceID: source.id,
                overwrite: true, reviewedFocus: "过时的确认值")
        }
        repo.saveError = .diskFull
        #expect(throws: (any Error).self) {
            try store.applyNextFocusProjectUpdate(profileID: source.profileId, sourceID: source.id,
                overwrite: true, reviewedFocus: "别人修改的重点")
        }
        #expect(project.currentFocus == "别人修改的重点")
        repo.saveError = nil
        try store.applyNextFocusProjectUpdate(profileID: source.profileId, sourceID: source.id,
            overwrite: true, reviewedFocus: "别人修改的重点")
        #expect(project.currentFocus == action.text)
        #expect(try store.suggestions.document(source.profileId).drafts[source.id.uuidString]?.pendingProjectUpdate == nil)
    }
}
