//
//  PracticeStoreTests.swift
//  foxgitaTests
//

import Foundation
import Testing

@testable import foxgita

@MainActor
struct PracticeStoreTests {
    private func makeStore(seeded: Bool = false) -> (PracticeStore, InMemoryPracticeRepository, UserDefaults) {
        let repo = InMemoryPracticeRepository()
        let defaults = UserDefaults(suiteName: "foxgita.tests.\(UUID().uuidString)")!
        defaults.set(seeded, forKey: SeedData.seededKey)
        return (PracticeStore(repository: repo, defaults: defaults), repo, defaults)
    }

    private func seedTemplate(into repo: InMemoryPracticeRepository) throws {
        let template = TaskItem(
            id: "tpl-chord", title: "和弦模板", subtitle: "8 分钟",
            category: .chord, targetMin: 8, sortOrder: 10, isTemplate: true
        )
        try repo.add(template)
        try repo.save()
    }

    private func seedActive(into repo: InMemoryPracticeRepository, id: String = "warm") throws {
        let task = TaskItem(
            id: id, title: "指尖热身", subtitle: "开放弦",
            category: .left, targetMin: 5, sortOrder: 0
        )
        try repo.add(task)
        try repo.save()
    }

    // MARK: - Seed

    @Test func seedOnlyRunsOnce() {
        let (store, repo, defaults) = makeStore(seeded: false)
        store.seedIfNeeded()
        #expect(defaults.bool(forKey: SeedData.seededKey))
        let firstCount = (try? repo.tasks().count) ?? 0
        #expect(firstCount > 0)

        store.seedIfNeeded()
        #expect((try? repo.tasks().count) == firstCount)
    }

    // MARK: - Tasks

    @Test func activateTemplateCreatesActiveCopy() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedTemplate(into: repo)

        let id = store.activateTemplate("tpl-chord")
        #expect(id == "active-tpl-chord")
        let active = try #require(try repo.task(id: "active-tpl-chord"))
        #expect(active.isTemplate == false)
        #expect(active.title == "和弦模板")
        #expect(active.status == .active)
    }

    @Test func activateTemplateIsIdempotent() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedTemplate(into: repo)
        #expect(store.activateTemplate("tpl-chord") == "active-tpl-chord")
        #expect(store.activateTemplate("tpl-chord") == "active-tpl-chord")
        #expect(try repo.tasks().filter { $0.id.hasPrefix("active-") }.count == 1)
    }

    @Test func activateMissingTemplateSetsNotFound() {
        let (store, _, _) = makeStore(seeded: true)
        #expect(store.activateTemplate("missing") == nil)
        #expect(store.lastError == .notFound)
    }

    @Test func createCustomTaskClampsMinutesAndNamesEmpty() throws {
        let (store, repo, _) = makeStore(seeded: true)
        let id = try #require(store.createCustomTask(name: "  ", minutes: 999, category: .scale))
        let task = try #require(try repo.task(id: id))
        #expect(task.targetMin == 60)
        #expect(task.title == "未命名练习")
        #expect(task.category == .scale)
    }

    @Test func setTaskStatusTouchesUpdatedAt() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let before = try #require(try repo.task(id: "warm")).updatedAt
        // Tiny delay so touch() is guaranteed to move the clock.
        Thread.sleep(forTimeInterval: 0.01)
        store.setTaskStatus("warm", to: .done)
        let after = try #require(try repo.task(id: "warm"))
        #expect(after.status == .done)
        #expect(after.updatedAt >= before)
    }

    // MARK: - Sessions

    @Test func finishSessionPersistsStepsAndRecordingRows() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(300)

        let ok = store.finishSession(
            taskId: "warm",
            steps: ["热身", "主练"],
            note: "感觉不错",
            startedAt: start,
            endedAt: end,
            durationSec: 300,
            bpm: 80,
            recordings: []
        )
        #expect(ok)
        let sessions = try repo.sessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].noteText == "感觉不错")
        #expect(sessions[0].durationSec == 300)
        #expect(try repo.task(id: "warm")?.steps == ["热身", "主练"])
    }

    @Test func finishSessionRejectsInvertedWindow() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let ok = store.finishSession(
            taskId: "warm", steps: [], note: "",
            startedAt: start, endedAt: start.addingTimeInterval(-10),
            durationSec: 10, bpm: 80, recordings: []
        )
        #expect(ok == false)
        #expect(store.lastError == .invalidInput)
        #expect(try repo.sessions().isEmpty)
    }

    @Test func finishSessionRejectsUnknownTask() {
        let (store, _, _) = makeStore(seeded: true)
        let now = Date()
        #expect(
            store.finishSession(
                taskId: "ghost", steps: [], note: "",
                startedAt: now, endedAt: now, durationSec: 0, bpm: 80, recordings: []
            ) == false
        )
        #expect(store.lastError == .notFound)
    }

    @Test func finishSessionRollsBackWhenSaveFails() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        repo.saveError = .diskFull
        let now = Date()
        #expect(
            store.finishSession(
                taskId: "warm", steps: ["x"], note: "",
                startedAt: now, endedAt: now, durationSec: 0, bpm: 80, recordings: []
            ) == false
        )
        #expect(store.lastError == .diskFull)
        // Session insert is pending and must not survive a failed save.
        #expect(try repo.sessions().isEmpty)
        #expect(repo.saveCount == 1) // only the seedActive save
    }

    // MARK: - Reset

    @Test func resetAllRestoresSeededCatalogue() throws {
        let (store, repo, defaults) = makeStore(seeded: true)
        try seedActive(into: repo, id: "custom-only")
        store.resetAll()
        #expect(defaults.bool(forKey: SeedData.seededKey))
        let tasks = try repo.tasks()
        #expect(tasks.contains { $0.id == "warm" })
        #expect(tasks.contains { $0.isTemplate })
        #expect(tasks.contains { $0.id == "custom-only" } == false)
    }
}
