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

    private func shanghai() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10,
        calendar: Calendar? = nil
    ) -> Date {
        let cal = calendar ?? shanghai()
        return cal.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour
        ))!
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

    // MARK: - Profile

    @Test func prepareCreatesOneActiveProfileAndBackfillsEmptyIds() throws {
        let (store, repo, _) = makeStore(seeded: false)
        let orphan = TaskItem(
            id: "orphan", title: "旧任务", subtitle: "",
            category: .left, targetMin: 5
        )
        try repo.add(orphan)
        try repo.save()
        #expect(orphan.profileId == "")

        store.prepare()

        let profile = try #require(try repo.activeProfile())
        #expect(profile.isActive)
        #expect(profile.memoryConsent == false)
        let tasks = try repo.tasks()
        #expect(tasks.contains { $0.id == "orphan" && $0.profileId == profile.id })
        #expect(tasks.filter(\.isTemplate).allSatisfy { $0.profileId == profile.id })

        store.prepare()
        #expect(try repo.profileCount() == 1)
    }

    @Test func createCustomTaskStampsCurrentProfileId() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profile = try #require(try repo.activeProfile())
        let id = try #require(store.createCustomTask(name: "自定义", minutes: 10, category: .chord))
        let task = try #require(try repo.task(id: id))
        #expect(task.profileId == profile.id)
    }

    @Test func prepareMapsEmptyConsentStateFromLegacyBool() throws {
        let (store, repo, _) = makeStore(seeded: true)
        let denied = try repo.ensureDefaultProfile()
        denied.memoryConsent = false
        denied.memoryConsentState = ""
        try repo.save()
        store.prepare()
        #expect(denied.consent == .undecided)
        #expect(denied.memoryConsent == false)

        denied.memoryConsent = true
        denied.memoryConsentState = ""
        try repo.save()
        store.prepare()
        #expect(denied.consent == .enabled)
        #expect(denied.memoryConsent == true)
    }

    // MARK: - Tasks

    @Test func activateTemplateCreatesActiveCopy() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedTemplate(into: repo)
        let cal = shanghai()
        let now = date(2026, 8, 19, calendar: cal)

        let id = store.activateTemplate("tpl-chord", now: now, calendar: cal)
        #expect(id == "active-tpl-chord")
        let active = try #require(try repo.task(id: "active-tpl-chord"))
        #expect(active.isTemplate == false)
        #expect(active.title == "和弦模板")
        #expect(active.status == .active)
        #expect(cal.isDate(active.startedOn ?? .distantPast, inSameDayAs: now))
    }

    @Test func activateTemplateIsIdempotent() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedTemplate(into: repo)
        let cal = shanghai()
        let now = date(2026, 8, 19, calendar: cal)
        #expect(store.activateTemplate("tpl-chord", now: now, calendar: cal) == "active-tpl-chord")
        #expect(store.activateTemplate("tpl-chord", now: now, calendar: cal) == "active-tpl-chord")
        #expect(try repo.tasks().filter { $0.id.hasPrefix("active-") }.count == 1)
    }

    @Test func activateTemplateReusesAcrossDays() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedTemplate(into: repo)
        let cal = shanghai()
        let day1 = date(2026, 8, 19, calendar: cal)
        let day2 = date(2026, 8, 20, calendar: cal)
        #expect(store.activateTemplate("tpl-chord", now: day1, calendar: cal) == "active-tpl-chord")
        #expect(store.activateTemplate("tpl-chord", now: day2, calendar: cal) == "active-tpl-chord")
        let active = try #require(try repo.task(id: "active-tpl-chord"))
        #expect(cal.isDate(active.startedOn ?? .distantPast, inSameDayAs: day2))
        #expect(try repo.tasks().filter { $0.id.hasPrefix("active-") }.count == 1)
    }

    @Test func activateTemplateReusesLegacyIdWhenStartedToday() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedTemplate(into: repo)
        let cal = shanghai()
        let now = date(2026, 8, 19, calendar: cal)
        let legacy = TaskItem(
            id: "active-tpl-chord", title: "和弦模板", subtitle: "8 分钟",
            category: .chord, targetMin: 8, startedOn: now, sortOrder: 10
        )
        try repo.add(legacy)
        try repo.save()
        #expect(store.activateTemplate("tpl-chord", now: now, calendar: cal) == "active-tpl-chord")
        #expect(try repo.task(id: "active-tpl-chord-2026-08-19") == nil)
    }

    @Test func activateTemplateReusesStableIdFromYesterday() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedTemplate(into: repo)
        let cal = shanghai()
        let yesterday = date(2026, 8, 18, calendar: cal)
        let today = date(2026, 8, 19, calendar: cal)
        let legacy = TaskItem(
            id: "active-tpl-chord", title: "和弦模板", subtitle: "8 分钟",
            category: .chord, targetMin: 8, startedOn: yesterday, sortOrder: 10
        )
        try repo.add(legacy)
        try repo.save()
        #expect(store.activateTemplate("tpl-chord", now: today, calendar: cal) == "active-tpl-chord")
        let active = try #require(try repo.task(id: "active-tpl-chord"))
        #expect(cal.isDate(active.startedOn ?? .distantPast, inSameDayAs: today))
    }

    @Test func activateTemplateDoesNotReviveDeleted() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedTemplate(into: repo)
        let cal = shanghai()
        let now = date(2026, 8, 19, calendar: cal)
        let id = try #require(store.activateTemplate("tpl-chord", now: now, calendar: cal))
        store.softDeleteTask(id)
        #expect(try repo.task(id: id) == nil)
        #expect(store.activateTemplate("tpl-chord", now: now, calendar: cal) == nil)
        #expect(try repo.taskIncludingDeleted(id: id)?.deletedAt != nil)
        #expect(try repo.tasks().filter { $0.id.hasPrefix("active-") }.count == 0)
    }

    @Test func isTemplateOriginDeletedReflectsSoftDelete() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedTemplate(into: repo)
        let cal = shanghai()
        let now = date(2026, 8, 19, calendar: cal)
        let id = try #require(store.activateTemplate("tpl-chord", now: now, calendar: cal))
        #expect(store.isTemplateOriginDeleted("tpl-chord") == false)
        store.softDeleteTask(id)
        #expect(store.isTemplateOriginDeleted("tpl-chord") == true)
    }

    @Test func ensureForTodaySetsStartedOn() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let cal = shanghai()
        let yesterday = date(2026, 8, 18, calendar: cal)
        let today = date(2026, 8, 19, calendar: cal)
        let task = try #require(try repo.task(id: "warm"))
        task.startedOn = yesterday
        task.status = .done
        try repo.save()

        #expect(store.ensureForToday("warm", now: today) == "warm")
        let after = try #require(try repo.task(id: "warm"))
        #expect(after.status == .active)
        #expect(after.startedOn == today)

        store.softDeleteTask("warm")
        #expect(store.ensureForToday("warm", now: today) == nil)
        #expect(store.lastError == .notFound)
        #expect(store.ensureForToday("missing", now: today) == nil)
        #expect(store.lastError == .notFound)
    }

    @Test func activateTemplateReactivatesDoneInstanceSameDay() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedTemplate(into: repo)
        let cal = shanghai()
        let now = date(2026, 8, 19, calendar: cal)
        let id = try #require(store.activateTemplate("tpl-chord", now: now, calendar: cal))
        store.setTaskStatus(id, to: .done)
        #expect(store.activateTemplate("tpl-chord", now: now, calendar: cal) == id)
        #expect(try repo.task(id: id)?.status == .active)
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

    @Test func createFromAIDraftPersistsSteps() throws {
        let (store, repo, _) = makeStore(seeded: true)
        let draft = AIPracticeDraft(
            title: "扫弦入门",
            category: .rhythm,
            targetMin: 12,
            steps: ["熟悉下下上", "60 BPM", "80 BPM"],
            chords: []
        )
        let id = try #require(store.createFromAIDraft(draft))
        let task = try #require(try repo.task(id: id))
        #expect(task.title == "扫弦入门")
        #expect(task.category == .rhythm)
        #expect(task.targetMin == 12)
        #expect(task.steps == ["熟悉下下上", "60 BPM", "80 BPM"])
        #expect(task.subtitle.contains("AI"))
        #expect(task.steps != ["新步骤"])
    }

    @Test func createFromAIDraftEncodesChordsInSubtitle() throws {
        let (store, repo, _) = makeStore(seeded: true)
        let draft = AIPracticeDraft(
            title: "转换",
            category: .chord,
            targetMin: 10,
            steps: ["识别和弦顺序 · 2 分钟"],
            chords: ["C", "G", "Am", "F"]
        )
        let id = try #require(store.createFromAIDraft(draft))
        let task = try #require(try repo.task(id: id))
        #expect(task.subtitle == "AI · 10 分钟 · C · G · Am · F")
        #expect(task.steps == ["识别和弦顺序 · 2 分钟"])
    }

    @Test func createFromAIDraftReusesSameOriginKey() throws {
        let (store, repo, _) = makeStore(seeded: true)
        let cal = shanghai()
        let yesterday = date(2026, 8, 18, calendar: cal)
        let key = PracticeTaskOrigin.photoOriginKey(generationId: "g1")
        let firstId = try #require(store.createFromAIDraft(
            AIPracticeDraft(
                title: "扫弦入门", category: .rhythm, targetMin: 12,
                steps: ["熟悉下下上"], chords: []
            ),
            originKey: key
        ))
        let first = try #require(try repo.task(id: firstId))
        first.startedOn = yesterday
        first.status = .done
        try repo.save()

        let reusedId = try #require(store.createFromAIDraft(
            AIPracticeDraft(
                title: "扫弦进阶", category: .scale, targetMin: 15,
                steps: ["80 BPM"], chords: ["G"]
            ),
            originKey: key
        ))
        #expect(reusedId == firstId)
        let reused = try #require(try repo.task(id: firstId))
        #expect(reused.title == "扫弦进阶")
        #expect(reused.subtitle == "AI · 15 分钟 · G")
        #expect(reused.category == .scale)
        #expect(reused.targetMin == 15)
        #expect(reused.steps == ["80 BPM"])
        #expect(reused.originKey == key)
        #expect(reused.status == .active)
        #expect(cal.isDate(reused.startedOn ?? .distantPast, inSameDayAs: Date()))
        #expect(try repo.tasks().filter { $0.originKey == key }.count == 1)
    }

    @Test func createFromAIDraftDifferentOriginKeysStayDistinct() throws {
        let (store, repo, _) = makeStore(seeded: true)
        let draft = AIPracticeDraft(
            title: "转换", category: .chord, targetMin: 10,
            steps: ["识别"], chords: ["C"]
        )
        let photo = PracticeTaskOrigin.photoOriginKey(generationId: "g1")
        let next = PracticeTaskOrigin.nextOriginKey(generationId: "g1")
        let photoId = try #require(store.createFromAIDraft(draft, originKey: photo))
        let nextId = try #require(store.createFromAIDraft(draft, originKey: next))
        #expect(photoId != nextId)
        #expect(try repo.task(id: photoId)?.originKey == photo)
        #expect(try repo.task(id: nextId)?.originKey == next)

        let emptyA = try #require(store.createFromAIDraft(draft, originKey: "  "))
        let emptyB = try #require(store.createFromAIDraft(draft))
        #expect(Set([photoId, nextId, emptyA, emptyB]).count == 4)
        #expect(try repo.task(id: emptyA)?.originKey == "")
        #expect(try repo.task(id: emptyB)?.originKey == "")
    }

    @Test func createFromAIDraftIgnoresDeletedOriginAndCreatesNew() throws {
        let (store, repo, _) = makeStore(seeded: true)
        let key = PracticeTaskOrigin.photoOriginKey(generationId: "g-del")
        let oldId = try #require(store.createFromAIDraft(
            AIPracticeDraft(
                title: "旧稿", category: .left, targetMin: 8,
                steps: ["慢"], chords: []
            ),
            originKey: key
        ))
        store.softDeleteTask(oldId)
        #expect(try repo.task(id: oldId) == nil)

        let newId = try #require(store.createFromAIDraft(
            AIPracticeDraft(
                title: "新稿", category: .rhythm, targetMin: 9,
                steps: ["快"], chords: []
            ),
            originKey: key
        ))
        #expect(newId != oldId)
        #expect(try repo.taskIncludingDeleted(id: oldId)?.deletedAt != nil)
        let created = try #require(try repo.task(id: newId))
        #expect(created.originKey == key)
        #expect(created.title == "新稿")
        #expect(try repo.tasks().filter { $0.originKey == key }.count == 1)
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

        let id = store.finishSession(
            taskId: "warm",
            steps: ["热身", "主练"],
            note: "感觉不错",
            startedAt: start,
            endedAt: end,
            durationSec: 300,
            bpm: 72,
            recordings: []
        )
        #expect(id != nil)
        #expect(try repo.task(id: "warm")?.defaultBpm == 72)
        #expect(try repo.sessions()[0].id == id)
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
        #expect(ok == nil)
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
            ) == nil
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
                startedAt: now, endedAt: now, durationSec: 60, bpm: 80, recordings: []
            ) == nil
        )
        #expect(store.lastError == .diskFull)
        // Session insert is pending and must not survive a failed save.
        #expect(try repo.sessions().isEmpty)
        #expect(repo.saveCount == 1) // only the seedActive save
    }

    @Test func finishSessionRejectsEmptySession() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        #expect(
            store.finishSession(
                taskId: "warm", steps: [], note: "",
                startedAt: now, endedAt: now, durationSec: 0, bpm: 80, recordings: []
            ) == nil
        )
        #expect(store.lastError == .invalidInput)
        #expect(try repo.sessions().isEmpty)
    }

    @Test func updateTaskPracticeStateWritesStepsWithoutSession() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        #expect(try repo.task(id: "warm")?.steps.isEmpty == true)
        store.updateTaskPracticeState("warm", steps: ["热身", "主练"], bpm: 88)
        #expect(try repo.task(id: "warm")?.steps == ["热身", "主练"])
        #expect(try repo.task(id: "warm")?.defaultBpm == 88)
        #expect(try repo.sessions().isEmpty)
    }

    @Test func finishSessionAcceptsZeroDurationWithNote() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        #expect(
            store.finishSession(
                taskId: "warm", steps: [], note: "只记一句",
                startedAt: now, endedAt: now, durationSec: 0, bpm: 80, recordings: []
            ) != nil
        )
        #expect(try repo.sessions().count == 1)
        #expect(try repo.sessions()[0].noteText == "只记一句")
    }

    private func writeClip(
        id: String = UUID().uuidString,
        fileName: String? = nil,
        durationSec: Int = 8
    ) throws -> AudioRecorderService.Clip {
        let name = fileName ?? "open-\(UUID().uuidString).m4a"
        let url = RecordingStore.url(for: name)
        try Data([0x00]).write(to: url)
        return AudioRecorderService.Clip(
            id: id, fileName: name, bytes: 1,
            durationSec: durationSec, createdAt: Date(), label: ""
        )
    }

    @Test func beginOpenSessionWritesSessionAndClipId() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let clip = try writeClip(id: "c1")
        defer { RecordingStore.delete(fileName: clip.fileName) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let sid = store.beginOpenSession(
            taskId: "warm", steps: ["a"], note: "",
            startedAt: start, endedAt: start, durationSec: 0, bpm: 80,
            clip: clip
        )
        #expect(sid != nil)
        let session = try #require(try repo.session(id: sid!))
        #expect(session.recordings.count == 1)
        #expect(session.recordings[0].id == "c1")
        #expect(session.durationSec == 0)
        #expect(try repo.task(id: "warm")?.steps == ["a"])
    }

    @Test func beginOpenSessionMissingFileWritesNothing() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let clip = AudioRecorderService.Clip(
            id: "ghost", fileName: "missing-\(UUID().uuidString).m4a",
            bytes: 1, durationSec: 3, createdAt: Date(), label: ""
        )
        let now = Date()
        #expect(store.beginOpenSession(
            taskId: "warm", steps: [], note: "",
            startedAt: now, endedAt: now, durationSec: 0, bpm: 80, clip: clip
        ) == nil)
        #expect(store.lastError == .fileMissing)
        #expect(try repo.sessions().isEmpty)
    }

    @Test func appendRecordingAddsSecondClip() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        let clipA = try writeClip(id: "a")
        let clipB = try writeClip(id: "b")
        defer {
            RecordingStore.delete(fileName: clipA.fileName)
            RecordingStore.delete(fileName: clipB.fileName)
        }
        let sid = try #require(store.beginOpenSession(
            taskId: "warm", steps: [], note: "",
            startedAt: now, endedAt: now, durationSec: 0, bpm: 80,
            clip: clipA
        ))
        #expect(store.appendRecording(sessionId: sid, clip: clipB))
        #expect(try repo.session(id: sid)?.recordings.map(\.id).sorted() == ["a", "b"])
        #expect(try repo.sessions().count == 1)
    }

    @Test func updateOpenSessionWritesNoteAndDuration() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clip = try writeClip(id: "a")
        defer { RecordingStore.delete(fileName: clip.fileName) }
        let sid = try #require(store.beginOpenSession(
            taskId: "warm", steps: ["旧"], note: "",
            startedAt: start, endedAt: start, durationSec: 0, bpm: 80,
            clip: clip
        ))
        let end = start.addingTimeInterval(90)
        #expect(store.updateOpenSession(
            sessionId: sid, steps: ["新"], note: "记",
            endedAt: end, durationSec: 90, bpm: 88
        ))
        let session = try #require(try repo.session(id: sid))
        #expect(session.noteText == "记")
        #expect(session.durationSec == 90)
        #expect(session.bpm == 88)
        #expect(session.steps == ["新"])
        #expect(try repo.task(id: "warm")?.steps == ["新"])
    }

    @Test func updateOpenSessionAllowsZeroDurationWhenClipsExist() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        let clip = try writeClip(id: "a")
        defer { RecordingStore.delete(fileName: clip.fileName) }
        let sid = try #require(store.beginOpenSession(
            taskId: "warm", steps: [], note: "",
            startedAt: now, endedAt: now, durationSec: 0, bpm: 80,
            clip: clip
        ))
        #expect(store.updateOpenSession(
            sessionId: sid, steps: [], note: "",
            endedAt: now, durationSec: 0, bpm: 80
        ))
        #expect(try repo.session(id: sid)?.durationSec == 0)
    }

    @Test func beginOpenSessionDoesNotWriteDefaultBpm() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        let clip = try writeClip(id: "a")
        defer { RecordingStore.delete(fileName: clip.fileName) }
        #expect(try repo.task(id: "warm")?.defaultBpm == 80)
        _ = try #require(store.beginOpenSession(
            taskId: "warm", steps: [], note: "",
            startedAt: now, endedAt: now, durationSec: 0, bpm: 95,
            clip: clip
        ))
        #expect(try repo.task(id: "warm")?.defaultBpm == 80)
    }

    @Test func updateOpenSessionWritesDefaultBpm() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clip = try writeClip(id: "a")
        defer { RecordingStore.delete(fileName: clip.fileName) }
        let sid = try #require(store.beginOpenSession(
            taskId: "warm", steps: ["旧"], note: "",
            startedAt: start, endedAt: start, durationSec: 0, bpm: 80,
            clip: clip
        ))
        #expect(store.updateOpenSession(
            sessionId: sid, steps: ["新"], note: "记",
            endedAt: start.addingTimeInterval(90), durationSec: 90, bpm: 88
        ))
        #expect(try repo.task(id: "warm")?.defaultBpm == 88)
    }

    @Test func updateOpenSessionUnknownIdReturnsFalse() {
        let (store, _, _) = makeStore(seeded: true)
        let now = Date()
        #expect(!store.updateOpenSession(
            sessionId: "ghost", steps: [], note: "",
            endedAt: now, durationSec: 0, bpm: 80
        ))
        #expect(store.lastError == .notFound)
    }

    @Test func finishSessionRejectsEmptyDoesNotWriteBpm() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        #expect(
            store.finishSession(
                taskId: "warm", steps: [], note: "",
                startedAt: now, endedAt: now, durationSec: 0, bpm: 120, recordings: []
            ) == nil
        )
        #expect(try repo.task(id: "warm")?.defaultBpm == 80)
    }

    @Test func seedIfNeededWritesOnlyTemplates() throws {
        let (store, repo, defaults) = makeStore(seeded: false)
        store.seedIfNeeded()
        #expect(defaults.bool(forKey: SeedData.seededKey))
        let tasks = try repo.tasks()
        #expect(tasks.allSatisfy { $0.isTemplate })
        #expect(tasks.contains { $0.id == "warm" } == false)
        #expect(tasks.contains { $0.id.hasPrefix("tpl-") })
    }

    // MARK: - Reset

    @Test func resetAllRestoresTemplatesOnly() throws {
        let (store, repo, defaults) = makeStore(seeded: true)
        try seedActive(into: repo, id: "custom-only")
        store.resetAll()
        #expect(defaults.bool(forKey: SeedData.seededKey))
        let tasks = try repo.tasks()
        #expect(tasks.contains { $0.id == "warm" } == false)
        #expect(tasks.contains { $0.isTemplate })
        #expect(tasks.contains { $0.id == "custom-only" } == false)
    }

    @Test func resetAllStampsTemplatesWithActiveProfileId() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profile = try #require(try repo.activeProfile())

        store.resetAll()

        let tasks = try repo.tasks()
        #expect(!tasks.isEmpty)
        #expect(tasks.filter(\.isTemplate).allSatisfy { $0.profileId == profile.id })
        #expect(try repo.activeProfile()?.id == profile.id)
    }

    // MARK: - Review writes

    @Test func markPendingClearsReadyText() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        #expect(store.finishSession(
            taskId: "warm", steps: ["a"], note: "n",
            startedAt: now, endedAt: now, durationSec: 60, bpm: 72,
            recordings: []
        ) != nil)
        let session = try repo.sessions()[0]
        let rec = RecordingRef(id: "clip-1", fileName: "x.m4a", bytes: 1, durationSec: 8)
        rec.reviewStatus = .ready
        rec.reviewHighlight = "旧"
        rec.reviewFocus = "旧"
        rec.reviewNextAction = "旧"
        session.recordings.append(rec)
        try repo.save()

        store.markReviewsPending(recordingIds: ["clip-1"])
        let after = try #require(try repo.recording(id: "clip-1"))
        #expect(after.reviewStatus == .pending)
        #expect(after.reviewHighlight.isEmpty)
    }

    @Test func applyReviewWritesThreeFields() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        #expect(store.finishSession(
            taskId: "warm", steps: ["慢速"], note: "笔记",
            startedAt: now, endedAt: now, durationSec: 60, bpm: 80,
            recordings: []
        ) != nil)
        let session = try repo.sessions()[0]
        session.recordings.append(RecordingRef(id: "clip-2", fileName: "y.mov", bytes: 2, durationSec: 20))
        try repo.save()

        store.applyReview(
            recordingId: "clip-2",
            draft: MediaReviewDraft(highlight: "稳", focus: "F", nextAction: "70")
        )
        let rec = try #require(try repo.recording(id: "clip-2"))
        #expect(rec.reviewStatus == .ready)
        #expect(rec.reviewHighlight == "稳")

        let ctx = try #require(store.reviewContext(recordingId: "clip-2"))
        #expect(ctx.taskTitle == "指尖热身")
        #expect(ctx.bpm == 80)
        #expect(ctx.note == "笔记")
        #expect(ctx.fileName == "y.mov")
    }

    @Test func markFailedClearsText() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        #expect(store.finishSession(
            taskId: "warm", steps: [], note: "n",
            startedAt: now, endedAt: now, durationSec: 60, bpm: 80, recordings: []
        ) != nil)
        let session = try repo.sessions()[0]
        let rec = RecordingRef(id: "clip-3", fileName: "z.m4a", bytes: 1)
        rec.reviewStatus = .pending
        session.recordings.append(rec)
        try repo.save()

        store.markReviewsFailed(recordingIds: ["clip-3", "missing"])
        #expect(try repo.recording(id: "clip-3")?.reviewStatus == .failed)
    }

    @Test func applyVideoDiagnosisWritesFindingsAndSummary() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        #expect(store.finishSession(
            taskId: "warm", steps: ["慢速"], note: "笔记",
            startedAt: now, endedAt: now, durationSec: 60, bpm: 80, recordings: []
        ) != nil)
        let session = try repo.sessions()[0]
        session.recordings.append(RecordingRef(id: "clip-v", fileName: "y.mov", bytes: 2, durationSec: 40))
        try repo.save()

        store.applyVideoDiagnosis(
            recordingId: "clip-v",
            draft: VideoDiagnosisDraft(
                highlight: "稳", focus: "F", nextAction: "70",
                findings: [
                    VideoFinding(
                        startSec: 8, endSec: 28, title: "按弦",
                        evidence: "杂音", cause: "离品丝", action: "靠近"
                    )
                ]
            )
        )
        let rec = try #require(try repo.recording(id: "clip-v"))
        #expect(rec.reviewStatus == .ready)
        #expect(rec.reviewFocus == "F")
        #expect(rec.videoFindings.count == 1)
        #expect(rec.videoFindings[0].startSec == 8)
    }

    @Test func markPendingClearsFindingsJSON() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        #expect(store.finishSession(
            taskId: "warm", steps: ["a"], note: "n",
            startedAt: now, endedAt: now, durationSec: 60, bpm: 72, recordings: []
        ) != nil)
        let session = try repo.sessions()[0]
        let rec = RecordingRef(id: "clip-p", fileName: "x.mov", bytes: 1, durationSec: 8)
        rec.reviewStatus = .ready
        rec.videoFindings = [
            VideoFinding(startSec: 0, endSec: 10, title: "t", evidence: "e", cause: "c", action: "a")
        ]
        session.recordings.append(rec)
        try repo.save()

        store.markReviewsPending(recordingIds: ["clip-p"])
        let after = try #require(try repo.recording(id: "clip-p"))
        #expect(after.reviewStatus == .pending)
        #expect(after.videoFindings.isEmpty)
    }

    @Test func updateThenFinishWithoutOpenIdCreatesSecondSession() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clip = try writeClip(id: "a")
        defer { RecordingStore.delete(fileName: clip.fileName) }
        let sid = try #require(store.beginOpenSession(
            taskId: "warm", steps: [], note: "一",
            startedAt: start, endedAt: start, durationSec: 10, bpm: 80,
            clip: clip
        ))
        #expect(store.updateOpenSession(
            sessionId: sid, steps: [], note: "一",
            endedAt: start.addingTimeInterval(10), durationSec: 10, bpm: 80
        ))
        let second = store.finishSession(
            taskId: "warm", steps: [], note: "二",
            startedAt: start.addingTimeInterval(100),
            endedAt: start.addingTimeInterval(130),
            durationSec: 30, bpm: 80, recordings: []
        )
        #expect(second != nil)
        #expect(second != sid)
        #expect(try repo.sessions().count == 2)
    }

    // MARK: - PracticeItem repository contract

    private func makePracticeItem(
        id: UUID = UUID(),
        profileId: UUID,
        dayKey: String = "2026-08-26",
        title: String = "开放弦",
        durationSeconds: Int = 60,
        deletedAt: Date? = nil
    ) -> PracticeItem {
        PracticeItem(
            id: id,
            profileId: profileId,
            practiceDayKey: dayKey,
            title: title,
            categoryRaw: PracticeCategory.left.rawValue,
            durationSeconds: durationSeconds,
            deletedAt: deletedAt
        )
    }

    @Test func practiceItemsIsolateByProfile() throws {
        let (_, repo, _) = makeStore(seeded: true)
        let profileA = UUID()
        let profileB = UUID()
        try repo.insertPracticeItem(makePracticeItem(profileId: profileA, title: "A"))
        try repo.insertPracticeItem(makePracticeItem(profileId: profileB, title: "B"))
        try repo.save()

        let itemsA = try repo.practiceItems(profileId: profileA)
        let itemsB = try repo.practiceItems(profileId: profileB)
        #expect(itemsA.map(\.title) == ["A"])
        #expect(itemsB.map(\.title) == ["B"])
        #expect(try repo.practiceItems(profileId: UUID()).isEmpty)
    }

    @Test func practiceItemFetchByIdRequiresMatchingLiveProfile() throws {
        let (_, repo, _) = makeStore(seeded: true)
        let profile = UUID()
        let other = UUID()
        let id = UUID()
        try repo.insertPracticeItem(makePracticeItem(id: id, profileId: profile, title: "抓取"))
        try repo.save()

        let found = try #require(try repo.practiceItem(id: id, profileId: profile))
        #expect(found.title == "抓取")
        #expect(try repo.practiceItem(id: id, profileId: other) == nil)
        #expect(try repo.practiceItem(id: UUID(), profileId: profile) == nil)
    }

    @Test func practiceItemsExcludeSoftDeletedFromDefaultCollection() throws {
        let (_, repo, _) = makeStore(seeded: true)
        let profile = UUID()
        let liveId = UUID()
        let deletedId = UUID()
        try repo.insertPracticeItem(makePracticeItem(id: liveId, profileId: profile, title: "在练"))
        try repo.insertPracticeItem(
            makePracticeItem(id: deletedId, profileId: profile, title: "已删", deletedAt: Date())
        )
        try repo.save()

        let items = try repo.practiceItems(profileId: profile)
        #expect(items.map(\.id) == [liveId])
        #expect(try repo.practiceItem(id: liveId, profileId: profile) != nil)
        #expect(try repo.practiceItem(id: deletedId, profileId: profile) == nil)
    }

    @Test func practiceItemsSameIdYieldsAtMostOne() throws {
        let (_, repo, _) = makeStore(seeded: true)
        let profile = UUID()
        let id = UUID()
        try repo.insertPracticeItem(makePracticeItem(id: id, profileId: profile, title: "第一次"))
        try repo.insertPracticeItem(makePracticeItem(id: id, profileId: profile, title: "第二次"))
        try repo.save()

        let matches = try repo.practiceItems(profileId: profile).filter { $0.id == id }
        #expect(matches.count == 1)
        #expect(try repo.practiceItem(id: id, profileId: profile) != nil)
    }

    @Test func practiceItemSnapshotsMapModelThroughStoreAdapter() throws {
        let (store, repo, _) = makeStore(seeded: true)
        let profile = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let live = PracticeItem(
            id: UUID(),
            profileId: profile,
            practiceDayKey: "2026-08-16",
            title: "音阶",
            categoryRaw: PracticeCategory.scale.rawValue,
            durationSeconds: 90,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let deleted = makePracticeItem(profileId: profile, title: "墓碑", deletedAt: Date())
        try repo.insertPracticeItem(live)
        try repo.insertPracticeItem(deleted)
        try repo.save()

        let snapshots = try store.practiceItemSnapshots(profileId: profile)
        #expect(snapshots.count == 1)
        #expect(snapshots[0] == PracticeItemSnapshot(
            id: live.id,
            practiceDayKey: "2026-08-16",
            createdAt: createdAt,
            title: "音阶",
            durationSeconds: 90,
            isDeleted: false,
            note: "",
            recordingCount: 0,
            categoryRaw: PracticeCategory.scale.rawValue
        ))

        let deletedSnapshot = PracticeStore.snapshot(from: deleted)
        #expect(deletedSnapshot.isDeleted)
        #expect(deletedSnapshot.title == "墓碑")
    }

    @Test func snapshotRecordingCountIgnoresSoftDeletedMedia() {
        let profile = UUID()
        let live = RecordingRef(id: "live", fileName: "live.m4a", bytes: 1, durationSec: 8)
        let deletedOnMixed = RecordingRef(id: "gone-mixed", fileName: "gone-mixed.m4a", bytes: 1, durationSec: 8)
        deletedOnMixed.deletedAt = Date()
        let mixed = makePracticeItem(profileId: profile, durationSeconds: 0)
        mixed.note = ""
        mixed.recordings = [live, deletedOnMixed]
        #expect(PracticeStore.snapshot(from: mixed).recordingCount == 1)

        let onlyDeletedClip = RecordingRef(id: "gone-only", fileName: "gone-only.m4a", bytes: 1, durationSec: 8)
        onlyDeletedClip.deletedAt = Date()
        let onlyDeleted = makePracticeItem(profileId: profile, durationSeconds: 0)
        onlyDeleted.note = ""
        onlyDeleted.recordings = [onlyDeletedClip]
        let snapshot = PracticeStore.snapshot(from: onlyDeleted)
        #expect(snapshot.recordingCount == 0)
        #expect(PracticeItemRules.isEffective(snapshot) == false)
    }

    // MARK: - PracticeItem create and absolute save

    private func makeInput(
        title: String = "开放弦",
        category: PracticeCategory = .left,
        source: PracticeItemSource = .custom,
        originId: String? = "origin-1",
        bpm: Int? = 80,
        timeSignature: String? = "4/4"
    ) -> PracticeItemInput {
        PracticeItemInput(
            title: title,
            category: category,
            source: source,
            originId: originId,
            bpm: bpm,
            timeSignature: timeSignature
        )
    }

    private func activeProfileId(_ repo: InMemoryPracticeRepository) throws -> UUID {
        let profile = try #require(try repo.activeProfile())
        return try #require(UUID(uuidString: profile.id))
    }

    @Test func createPracticeItemPersistsImmediatelyWithoutLegacyCompanions() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let now = date(2026, 8, 26, 21, calendar: cal)
        let tasksBefore = try repo.tasks().count
        let sessionsBefore = try repo.sessions().count

        let created = try store.createPracticeItem(input: makeInput(), now: now, calendar: cal)

        let fetched = try #require(try repo.practiceItem(id: created.id, profileId: profileId))
        #expect(fetched.id == created.id)
        #expect(fetched.profileId == profileId)
        #expect(fetched.title == "开放弦")
        #expect(fetched.categoryRaw == PracticeCategory.left.rawValue)
        #expect(fetched.sourceRaw == PracticeItemSource.custom.rawValue)
        #expect(fetched.originId == "origin-1")
        #expect(fetched.bpm == 80)
        #expect(fetched.timeSignature == "4/4")
        #expect(fetched.durationSeconds == 0)
        #expect(fetched.note == "")
        #expect(fetched.practiceDayKey == PracticeDayKey.make(from: now, calendar: cal))
        #expect(fetched.createdAt == now)
        #expect(fetched.updatedAt == now)
        #expect(fetched.deletedAt == nil)
        #expect(try repo.practiceItems(profileId: profileId).map(\.id) == [created.id])
        #expect(try repo.tasks().count == tasksBefore)
        #expect(try repo.sessions().count == sessionsBefore)
    }

    @Test func savePracticeItem600TwiceStays600() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let created = try store.createPracticeItem(
            input: makeInput(), now: date(2026, 8, 26, calendar: cal), calendar: cal
        )

        try store.savePracticeItem(id: created.id, durationSeconds: 600, note: "第一遍", now: date(2026, 8, 26, 11, calendar: cal))
        try store.savePracticeItem(id: created.id, durationSeconds: 600, note: "第二遍", now: date(2026, 8, 26, 12, calendar: cal))

        let fetched = try #require(try repo.practiceItem(id: created.id, profileId: profileId))
        #expect(fetched.durationSeconds == 600)
        #expect(fetched.note == "第二遍")
        #expect(try repo.practiceItems(profileId: profileId).filter { $0.id == created.id }.count == 1)
    }

    @Test func savePracticeItemDoesNotChangePracticeDayKey() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let createdAt = date(2026, 8, 26, 23, calendar: cal)
        let created = try store.createPracticeItem(input: makeInput(), now: createdAt, calendar: cal)

        try store.savePracticeItem(
            id: created.id,
            durationSeconds: 120,
            note: "跨夜保存",
            now: date(2026, 8, 27, 1, calendar: cal)
        )

        let fetched = try #require(try repo.practiceItem(id: created.id, profileId: profileId))
        #expect(fetched.practiceDayKey == "2026-08-26")
        #expect(fetched.practiceDayKey == PracticeDayKey.make(from: createdAt, calendar: cal))
        #expect(fetched.durationSeconds == 120)
    }

    @Test func savePracticeItemClampsNegativeDurationToZero() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let now = date(2026, 8, 26, 15, calendar: cal)
        let created = try store.createPracticeItem(input: makeInput(), now: now, calendar: cal)

        try store.savePracticeItem(id: created.id, durationSeconds: -15, note: "无效计时", now: now)

        let fetched = try #require(try repo.practiceItem(id: created.id, profileId: profileId))
        #expect(fetched.durationSeconds == 0)
        #expect(fetched.note == "无效计时")
        #expect(fetched.updatedAt == now)
        #expect(fetched.practiceDayKey == "2026-08-26")
    }

    @Test func repeatedSaveOnSameDetailOverwritesAndDoesNotAccumulate() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let created = try store.createPracticeItem(
            input: makeInput(), now: date(2026, 8, 26, calendar: cal), calendar: cal
        )

        try store.savePracticeItem(id: created.id, durationSeconds: 180, note: "保存", now: date(2026, 8, 26, 11, calendar: cal))
        try store.savePracticeItem(id: created.id, durationSeconds: 420, note: "再保存", now: date(2026, 8, 26, 12, calendar: cal))
        try store.savePracticeItem(id: created.id, durationSeconds: 420, note: "再保存", now: date(2026, 8, 26, 12, calendar: cal))

        let fetched = try #require(try repo.practiceItem(id: created.id, profileId: profileId))
        #expect(fetched.durationSeconds == 420)
        #expect(try repo.practiceItems(profileId: profileId).filter { $0.id == created.id }.count == 1)
    }

    @Test func onDisappearSaveAfterButtonSaveDoesNotAccumulate() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let created = try store.createPracticeItem(
            input: makeInput(), now: date(2026, 8, 26, calendar: cal), calendar: cal
        )
        let now = date(2026, 8, 26, 14, calendar: cal)

        try store.savePracticeItem(id: created.id, durationSeconds: 600, note: "点保存", now: now)
        try store.savePracticeItem(id: created.id, durationSeconds: 600, note: "离开自动保存", now: now)

        let fetched = try #require(try repo.practiceItem(id: created.id, profileId: profileId))
        #expect(fetched.durationSeconds == 600)
        #expect(fetched.note == "离开自动保存")
        #expect(try repo.practiceItems(profileId: profileId).count == 1)
    }

    @Test func reenterThenSaveUsesStoredDurationAndDoesNotAccumulate() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let created = try store.createPracticeItem(
            input: makeInput(), now: date(2026, 8, 26, calendar: cal), calendar: cal
        )
        try store.savePracticeItem(
            id: created.id, durationSeconds: 600, note: "离开前", now: date(2026, 8, 26, 16, calendar: cal)
        )

        let reentered = try #require(try repo.practiceItem(id: created.id, profileId: profileId))
        let baseDuration = reentered.durationSeconds
        try store.savePracticeItem(
            id: reentered.id,
            durationSeconds: baseDuration,
            note: "重进后再保存",
            now: date(2026, 8, 26, 17, calendar: cal)
        )

        let fetched = try #require(try repo.practiceItem(id: created.id, profileId: profileId))
        #expect(baseDuration == 600)
        #expect(fetched.durationSeconds == 600)
        #expect(fetched.note == "重进后再保存")
        #expect(try repo.practiceItems(profileId: profileId).filter { $0.id == created.id }.count == 1)
    }

    @Test func softDeletePracticeItemSetsDeletedAtAndHidesFromQueries() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let created = try store.createPracticeItem(
            input: makeInput(title: "待删"), now: date(2026, 8, 26, calendar: cal), calendar: cal
        )
        let deletedAt = date(2026, 8, 26, 18, calendar: cal)

        try store.softDeletePracticeItem(id: created.id, now: deletedAt)

        #expect(created.deletedAt == deletedAt)
        #expect(try repo.practiceItem(id: created.id, profileId: profileId) == nil)
        #expect(try repo.practiceItems(profileId: profileId).isEmpty)
        #expect(PracticeStore.snapshot(from: created).isDeleted)
    }

    // MARK: - Recording ownership on PracticeItem

    @Test func attachRecordingDoesNotCreateSession() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let item = try store.createPracticeItem(
            input: makeInput(), now: date(2026, 8, 26, calendar: cal), calendar: cal
        )
        let sessionsBefore = try repo.sessions().count
        let clip = try writeClip(id: "item-new")
        defer { RecordingStore.delete(fileName: clip.fileName) }
        let recording = RecordingRef(
            id: clip.id, fileName: clip.fileName, bytes: clip.bytes,
            durationSec: clip.durationSec, createdAt: clip.createdAt, label: clip.label
        )

        try store.attachRecording(recording, toPracticeItemId: item.id)

        #expect(try repo.sessions().count == sessionsBefore)
        let stored = try #require(try repo.recording(id: clip.id))
        #expect(stored.session == nil)
        #expect(stored.practiceItem?.id == item.id)
        #expect(try repo.practiceItem(id: item.id, profileId: profileId)?.recordings.map(\.id) == [clip.id])
        #expect(store.practiceReviewContext(recordingId: clip.id) == .practiceItem(item.id))
        let media = try #require(store.reviewContext(recordingId: clip.id))
        #expect(media.taskTitle == item.title)
        #expect(media.note == item.note)
        #expect(media.fileName == clip.fileName)
    }

    @Test func deletingPracticeItemCascadesItsRecordings() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let cal = shanghai()
        let item = try store.createPracticeItem(
            input: makeInput(), now: date(2026, 8, 26, calendar: cal), calendar: cal
        )
        let clip = try writeClip(id: "item-cascade")
        defer { RecordingStore.delete(fileName: clip.fileName) }
        let recording = RecordingRef(
            id: clip.id, fileName: clip.fileName, bytes: clip.bytes, durationSec: clip.durationSec
        )
        try store.attachRecording(recording, toPracticeItemId: item.id)
        #expect(try repo.recording(id: clip.id) != nil)

        repo.removePracticeItem(id: item.id)

        #expect(try repo.recording(id: clip.id) == nil)
        #expect(try repo.sessions().isEmpty)
        #expect(store.practiceReviewContext(recordingId: clip.id) == nil)
    }

    @Test func legacySessionRecordingsRemainReadable() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        store.prepare()
        let now = Date()
        #expect(store.finishSession(
            taskId: "warm", steps: ["慢速"], note: "旧笔记",
            startedAt: now, endedAt: now, durationSec: 60, bpm: 80,
            recordings: []
        ) != nil)
        let session = try repo.sessions()[0]
        session.recordings.append(RecordingRef(id: "legacy-clip", fileName: "legacy.m4a", bytes: 1, durationSec: 12))
        try repo.save()

        let stored = try #require(try repo.recording(id: "legacy-clip"))
        #expect(stored.practiceItem == nil)
        let sessionId = try #require(UUID(uuidString: session.id))
        #expect(store.practiceReviewContext(recordingId: "legacy-clip") == .legacySession(sessionId))
        let media = try #require(store.reviewContext(recordingId: "legacy-clip"))
        #expect(media.taskTitle == "指尖热身")
        #expect(media.bpm == 80)
        #expect(media.note == "旧笔记")
        #expect(media.fileName == "legacy.m4a")
    }

    @Test func attachRecordingMissingFileDoesNotWrite() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let item = try store.createPracticeItem(
            input: makeInput(), now: date(2026, 8, 26, calendar: shanghai()), calendar: shanghai()
        )
        let recording = RecordingRef(
            id: "missing-clip",
            fileName: "missing-\(UUID().uuidString).m4a",
            bytes: 1
        )

        #expect(throws: StoreError.fileMissing) {
            try store.attachRecording(recording, toPracticeItemId: item.id)
        }
        #expect(store.lastError == .fileMissing)
        #expect(try repo.recording(id: "missing-clip") == nil)
        #expect(item.recordings.isEmpty)
        #expect(try repo.sessions().isEmpty)
    }

    @Test func gcOrphanRecordingsKeepsPracticeItemClips() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let item = try store.createPracticeItem(
            input: makeInput(), now: date(2026, 8, 26, calendar: shanghai()), calendar: shanghai()
        )
        let clip = try writeClip(id: "item-gc")
        let orphanName = "orphan-\(UUID().uuidString).m4a"
        try Data([0x01]).write(to: RecordingStore.url(for: orphanName))
        defer {
            RecordingStore.delete(fileName: clip.fileName)
            RecordingStore.delete(fileName: orphanName)
        }
        let recording = RecordingRef(
            id: clip.id, fileName: clip.fileName, bytes: clip.bytes, durationSec: clip.durationSec
        )
        try store.attachRecording(recording, toPracticeItemId: item.id)

        let removed = store.gcOrphanRecordings()
        #expect(removed >= 1)
        #expect(RecordingStore.fileExists(fileName: clip.fileName))
        #expect(!RecordingStore.fileExists(fileName: orphanName))
        #expect(try repo.recording(id: clip.id) != nil)
    }

    @Test func gcOrphanRecordingsReturnsZeroWhenFetchFails() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let item = try store.createPracticeItem(
            input: makeInput(), now: date(2026, 8, 26, calendar: shanghai()), calendar: shanghai()
        )
        let clip = try writeClip(id: "item-gc-fail")
        defer { RecordingStore.delete(fileName: clip.fileName) }
        let recording = RecordingRef(
            id: clip.id, fileName: clip.fileName, bytes: clip.bytes, durationSec: clip.durationSec
        )
        try store.attachRecording(recording, toPracticeItemId: item.id)
        repo.fetchError = .saveFailed

        let removed = store.gcOrphanRecordings()
        #expect(removed == 0)
        #expect(RecordingStore.fileExists(fileName: clip.fileName))
        #expect(try repo.recording(id: clip.id) != nil)
    }

    // MARK: - Daily item entry points

    private func sampleDraft(
        title: String = "扫弦入门",
        category: PracticeCategory = .rhythm
    ) -> AIPracticeDraft {
        AIPracticeDraft(
            title: title,
            category: category,
            targetMin: 12,
            steps: ["熟悉下下上"],
            chords: ["G"]
        )
    }

    private func expectSoloCreatedItem(
        _ item: PracticeItem,
        repo: InMemoryPracticeRepository,
        profileId: UUID,
        tasksBefore: Int,
        sessionsBefore: Int
    ) throws {
        #expect(try repo.practiceItems(profileId: profileId).map(\.id) == [item.id])
        #expect(try repo.practiceItem(id: item.id, profileId: profileId)?.id == item.id)
        #expect(try repo.tasks().count == tasksBefore)
        #expect(try repo.sessions().count == sessionsBefore)
        #expect(
            PracticeDetailState.practiceRoute(fromSheetSelection: item.id.uuidString)
                == .detail(itemId: item.id)
        )
    }

    @Test func customEntryCreatesOnePracticeItemWithoutTaskOrSession() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let now = date(2026, 8, 26, 9, calendar: cal)
        let tasksBefore = try repo.tasks().count
        let sessionsBefore = try repo.sessions().count
        let gate = PracticeEntryGate()

        let created = try gate.submit(
            store: store,
            input: PracticeEntry.custom(name: "  F 和弦转换  ", category: .chord),
            token: PracticeEntryToken(),
            now: now,
            calendar: cal
        )

        try expectSoloCreatedItem(
            created, repo: repo, profileId: profileId,
            tasksBefore: tasksBefore, sessionsBefore: sessionsBefore
        )
        #expect(created.title == "F 和弦转换")
        #expect(created.categoryRaw == PracticeCategory.chord.rawValue)
        #expect(created.sourceRaw == PracticeItemSource.custom.rawValue)
        #expect(created.originId == nil)
        #expect(created.durationSeconds == 0)
        #expect(created.practiceDayKey == "2026-08-26")
        #expect(try repo.tasks().contains { $0.id.hasPrefix("custom-") } == false)
    }

    @Test func recommendEntryCopiesTemplateWithoutActivatingTask() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedTemplate(into: repo)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let now = date(2026, 8, 26, 10, calendar: cal)
        let template = try #require(try repo.task(id: "tpl-chord"))
        let tasksBefore = try repo.tasks().count
        let sessionsBefore = try repo.sessions().count
        let gate = PracticeEntryGate()

        let created = try gate.submit(
            store: store,
            input: PracticeEntry.recommend(from: template),
            token: PracticeEntryToken(),
            now: now,
            calendar: cal
        )

        try expectSoloCreatedItem(
            created, repo: repo, profileId: profileId,
            tasksBefore: tasksBefore, sessionsBefore: sessionsBefore
        )
        #expect(created.title == "和弦模板")
        #expect(created.categoryRaw == PracticeCategory.chord.rawValue)
        #expect(created.sourceRaw == PracticeItemSource.recommend.rawValue)
        #expect(created.bpm == template.defaultBpm)
        #expect(created.timeSignature == template.timeSig)
        #expect(try repo.task(id: "tpl-chord")?.isTemplate == true)
        #expect(try repo.task(id: "active-tpl-chord") == nil)
    }

    @Test func photoEntryCreatesOnePracticeItemFromDraft() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let now = date(2026, 8, 26, 11, calendar: cal)
        let tasksBefore = try repo.tasks().count
        let sessionsBefore = try repo.sessions().count
        let gate = PracticeEntryGate()
        let generationId = "photo-gen-1"

        let created = try gate.submit(
            store: store,
            input: PracticeEntry.photo(draft: sampleDraft(), generationId: generationId),
            token: PracticeEntryToken(),
            now: now,
            calendar: cal
        )

        try expectSoloCreatedItem(
            created, repo: repo, profileId: profileId,
            tasksBefore: tasksBefore, sessionsBefore: sessionsBefore
        )
        #expect(created.title == "扫弦入门")
        #expect(created.categoryRaw == PracticeCategory.rhythm.rawValue)
        #expect(created.sourceRaw == PracticeItemSource.photo.rawValue)
        #expect(created.originId == PracticeTaskOrigin.photoOriginKey(generationId: generationId))
        #expect(try repo.tasks().contains { $0.originKey == created.originId } == false)
    }

    @Test func nextEntryCreatesOnePracticeItemFromDraft() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let now = date(2026, 8, 26, 12, calendar: cal)
        let tasksBefore = try repo.tasks().count
        let sessionsBefore = try repo.sessions().count
        let gate = PracticeEntryGate()
        let generationId = "next-gen-1"

        let created = try gate.submit(
            store: store,
            input: PracticeEntry.next(draft: sampleDraft(title: "今日安排", category: .scale), generationId: generationId),
            token: PracticeEntryToken(),
            now: now,
            calendar: cal
        )

        try expectSoloCreatedItem(
            created, repo: repo, profileId: profileId,
            tasksBefore: tasksBefore, sessionsBefore: sessionsBefore
        )
        #expect(created.title == "今日安排")
        #expect(created.categoryRaw == PracticeCategory.scale.rawValue)
        #expect(created.sourceRaw == PracticeItemSource.next.rawValue)
        #expect(created.originId == PracticeTaskOrigin.nextOriginKey(generationId: generationId))
        #expect(try repo.tasks().contains { $0.originKey == created.originId } == false)
    }

    @Test func sameActionTokenTwiceCreatesOnePracticeItem() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let now = date(2026, 8, 26, 13, calendar: cal)
        let tasksBefore = try repo.tasks().count
        let gate = PracticeEntryGate()
        let token = PracticeEntryToken()
        let input = PracticeEntry.custom(name: "开放弦", category: .left)

        let first = try gate.submit(store: store, input: input, token: token, now: now, calendar: cal)
        let second = try gate.submit(store: store, input: input, token: token, now: now, calendar: cal)

        #expect(first.id == second.id)
        #expect(try repo.practiceItems(profileId: profileId).map(\.id) == [first.id])
        #expect(try repo.tasks().count == tasksBefore)
        #expect(try repo.sessions().isEmpty)
        #expect(
            PracticeDetailState.practiceRoute(fromSheetSelection: second.id.uuidString)
                == .detail(itemId: first.id)
        )
    }

    @Test func differentTokensWithSameTitleCreateTwoPracticeItems() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let now = date(2026, 8, 26, 14, calendar: cal)
        let gate = PracticeEntryGate()
        let input = PracticeEntry.custom(name: "开放弦", category: .left)

        let first = try gate.submit(
            store: store, input: input, token: PracticeEntryToken(), now: now, calendar: cal
        )
        let second = try gate.submit(
            store: store, input: input, token: PracticeEntryToken(), now: now, calendar: cal
        )

        #expect(first.id != second.id)
        #expect(first.title == second.title)
        #expect(Set(try repo.practiceItems(profileId: profileId).map(\.id)) == [first.id, second.id])
        #expect(try repo.tasks().isEmpty)
        #expect(try repo.sessions().isEmpty)
    }

    @Test func photoOriginRetryWithDifferentTokensReusesOneItem() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let now = date(2026, 8, 26, 15, calendar: cal)
        let gate = PracticeEntryGate()
        let generationId = "photo-retry"
        let input = PracticeEntry.photo(draft: sampleDraft(), generationId: generationId)

        let first = try gate.submit(
            store: store, input: input, token: PracticeEntryToken(), now: now, calendar: cal
        )
        let second = try gate.submit(
            store: store, input: input, token: PracticeEntryToken(), now: now, calendar: cal
        )

        #expect(first.id == second.id)
        #expect(try repo.practiceItems(profileId: profileId).count == 1)
        #expect(try repo.tasks().isEmpty)
    }

    @Test func cancelWithoutSubmitCreatesNoPracticeItem() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let tasksBefore = try repo.tasks().count
        _ = PracticeEntryGate()

        #expect(try repo.practiceItems(profileId: profileId).isEmpty)
        #expect(try repo.tasks().count == tasksBefore)
        #expect(try repo.sessions().isEmpty)
    }

    @Test func generationFailureLeavesNoPracticeItem() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let now = date(2026, 8, 26, 16, calendar: cal)
        let tasksBefore = try repo.tasks().count
        let gate = PracticeEntryGate()

        let created = try gate.commitIfSucceeded(
            false,
            store: store,
            input: PracticeEntry.photo(draft: sampleDraft(), generationId: "fail-gen"),
            token: PracticeEntryToken(),
            now: now,
            calendar: cal
        )

        #expect(created == nil)
        #expect(try repo.practiceItems(profileId: profileId).isEmpty)
        #expect(try repo.practiceItemsIncludingDeleted().isEmpty)
        #expect(try repo.tasks().count == tasksBefore)
        #expect(try repo.sessions().isEmpty)
    }

    @Test func generationSuccessAfterFailureCreatesOneItem() throws {
        let (store, repo, _) = makeStore(seeded: true)
        store.prepare()
        let profileId = try activeProfileId(repo)
        let cal = shanghai()
        let now = date(2026, 8, 26, 17, calendar: cal)
        let tasksBefore = try repo.tasks().count
        let gate = PracticeEntryGate()
        let input = PracticeEntry.next(draft: sampleDraft(title: "安排"), generationId: "ok-gen")

        #expect(
            try gate.commitIfSucceeded(
                false, store: store, input: input, token: PracticeEntryToken(), now: now, calendar: cal
            ) == nil
        )
        let created = try #require(
            try gate.commitIfSucceeded(
                true, store: store, input: input, token: PracticeEntryToken(), now: now, calendar: cal
            )
        )

        try expectSoloCreatedItem(
            created, repo: repo, profileId: profileId,
            tasksBefore: tasksBefore, sessionsBefore: 0
        )
        #expect(created.sourceRaw == PracticeItemSource.next.rawValue)
    }

    @Test func snapshotIncludesProjectId() throws {
        let (store, repo, _) = makeStore()
        store.prepare()
        let profileId = UUID(uuidString: try #require(repo.activeProfile()?.id))!
        let projectId = UUID()
        let item = PracticeItem(
            id: UUID(),
            profileId: profileId,
            practiceDayKey: "2026-08-28",
            title: "挂项目",
            categoryRaw: PracticeCategory.chord.rawValue,
            durationSeconds: 0,
            projectId: projectId
        )
        try repo.insertPracticeItem(item)
        try repo.save()
        #expect(PracticeStore.snapshot(from: item).projectId == projectId)
    }

    // MARK: - Project commands

    @Test func createProjectRejectsBlankNameAndGoal() throws {
        let (store, _, _) = makeStore()
        store.prepare()
        #expect(throws: StoreError.invalidInput) {
            try store.createProject(name: "  ", goal: "目标", kindRaw: "", stageRaw: "", currentFocus: "", now: Date())
        }
        #expect(throws: StoreError.invalidInput) {
            try store.createProject(name: "知足", goal: "  ", kindRaw: "", stageRaw: "", currentFocus: "", now: Date())
        }
    }

    @Test func createTodayPracticeItemUsesFocusTitleAndDoesNotMoveYesterday() throws {
        let (store, repo, _) = makeStore()
        store.prepare()
        let profileId = UUID(uuidString: try #require(repo.activeProfile()?.id))!
        let cal = shanghai()
        let yesterday = date(2026, 8, 27, calendar: cal)
        let today = date(2026, 8, 28, calendar: cal)
        let project = Project(profileId: profileId, name: "知足", goal: "完整弹唱", currentFocus: "副歌节奏")
        try repo.insertProject(project)
        try repo.save()
        let old = try store.createPracticeItem(
            input: PracticeItemInput(title: "昨天", category: .song, source: .custom, originId: nil, bpm: nil, timeSignature: nil),
            now: yesterday,
            calendar: cal
        )
        try store.setPracticeItemProject(id: old.id, projectId: project.id, now: yesterday)
        let created = try store.createTodayPracticeItem(projectId: project.id, now: today, calendar: cal)
        #expect(created.practiceDayKey == "2026-08-28")
        #expect(created.projectId == project.id)
        #expect(created.title == "副歌节奏")
        #expect(created.id != old.id)
        #expect(try repo.practiceItem(id: old.id, profileId: profileId)?.practiceDayKey == "2026-08-27")
        #expect(try repo.practiceItem(id: old.id, profileId: profileId)?.durationSeconds == 0)
    }

    @Test func deleteProjectClearsItemProjectIdAndPin() throws {
        let (store, repo, _) = makeStore()
        store.prepare()
        let profileId = UUID(uuidString: try #require(repo.activeProfile()?.id))!
        let project = Project(profileId: profileId, name: "知足", goal: "完整弹唱")
        try repo.insertProject(project)
        try repo.save()
        try store.setPinnedProjectId(project.id)
        let item = try store.createTodayPracticeItem(
            projectId: project.id,
            now: date(2026, 8, 28),
            calendar: shanghai()
        )
        try store.deleteProject(id: project.id, now: date(2026, 8, 28, 12))
        #expect(try repo.project(id: project.id, profileId: profileId) == nil)
        #expect(try repo.projectsIncludingDeleted().first { $0.id == project.id }?.deletedAt != nil)
        #expect(try repo.practiceItem(id: item.id, profileId: profileId)?.projectId == nil)
        #expect(try repo.activeProfile()?.pinnedProjectId == nil)
    }

    @Test func setPracticeItemProjectOnlyWritesProjectId() throws {
        let (store, repo, _) = makeStore()
        store.prepare()
        let cal = shanghai()
        let item = try store.createPracticeItem(
            input: PracticeItemInput(title: "独立", category: .chord, source: .custom, originId: nil, bpm: nil, timeSignature: nil),
            now: date(2026, 8, 28, calendar: cal),
            calendar: cal
        )
        let profileId = item.profileId
        let a = Project(profileId: profileId, name: "A", goal: "ga")
        let b = Project(profileId: profileId, name: "B", goal: "gb")
        try repo.insertProject(a)
        try repo.insertProject(b)
        try repo.save()
        try store.savePracticeItem(id: item.id, durationSeconds: 90, note: "n", now: date(2026, 8, 28, 11, calendar: cal))
        try store.setPracticeItemProject(id: item.id, projectId: a.id, now: date(2026, 8, 28, 12, calendar: cal))
        try store.setPracticeItemProject(id: item.id, projectId: b.id, now: date(2026, 8, 28, 13, calendar: cal))
        let live = try #require(try repo.practiceItem(id: item.id, profileId: profileId))
        #expect(live.projectId == b.id)
        #expect(live.practiceDayKey == "2026-08-28")
        #expect(live.durationSeconds == 90)
        #expect(live.note == "n")
        try store.setPracticeItemProject(id: item.id, projectId: nil, now: date(2026, 8, 28, 14, calendar: cal))
        #expect(try repo.practiceItem(id: item.id, profileId: profileId)?.projectId == nil)
    }

    @Test func setProjectVersionsReplaceAndClearWithoutTouchingItem() throws {
        let (store, repo, _) = makeStore()
        store.prepare()
        let cal = shanghai()
        let now = date(2026, 8, 28, calendar: cal)
        let project = try store.createProject(
            name: "知足", goal: "完整弹唱", kindRaw: "", stageRaw: "", currentFocus: "", now: now
        )
        let a = try store.createTodayPracticeItem(projectId: project.id, now: now, calendar: cal)
        try store.savePracticeItem(id: a.id, durationSeconds: 60, note: "a", now: date(2026, 8, 28, 11, calendar: cal))
        let b = try store.createTodayPracticeItem(
            projectId: project.id, now: date(2026, 8, 28, 12, calendar: cal), calendar: cal
        )
        try store.savePracticeItem(id: b.id, durationSeconds: 0, note: "b-note", now: date(2026, 8, 28, 13, calendar: cal))
        try store.setProjectStageVersion(projectId: project.id, itemId: a.id, now: date(2026, 8, 28, 14, calendar: cal))
        try store.setProjectFinalVersion(projectId: project.id, itemId: a.id, now: date(2026, 8, 28, 14, calendar: cal))
        try store.setProjectStageVersion(projectId: project.id, itemId: b.id, now: date(2026, 8, 28, 15, calendar: cal))
        let profileId = a.profileId
        let live = try #require(try repo.project(id: project.id, profileId: profileId))
        #expect(live.stageVersionItemId == b.id)
        #expect(live.finalVersionItemId == a.id)
        #expect(try repo.practiceItem(id: a.id, profileId: profileId)?.durationSeconds == 60)
        try store.setProjectFinalVersion(projectId: project.id, itemId: nil, now: date(2026, 8, 28, 16, calendar: cal))
        #expect(try repo.project(id: project.id, profileId: profileId)?.finalVersionItemId == nil)
        #expect(try repo.project(id: project.id, profileId: profileId)?.stageVersionItemId == b.id)
        #expect(try repo.practiceItem(id: a.id, profileId: profileId)?.note == "a")
    }

    @Test func setProjectVersionRejectsBlankItemAndWrongProject() throws {
        let (store, repo, _) = makeStore()
        store.prepare()
        let cal = shanghai()
        let now = date(2026, 8, 28, calendar: cal)
        let project = try store.createProject(
            name: "知足", goal: "完整弹唱", kindRaw: "", stageRaw: "", currentFocus: "", now: now
        )
        let blank = try store.createTodayPracticeItem(projectId: project.id, now: now, calendar: cal)
        #expect(throws: StoreError.invalidInput) {
            try store.setProjectStageVersion(projectId: project.id, itemId: blank.id, now: now)
        }
        #expect(try repo.project(id: project.id, profileId: blank.profileId)?.stageVersionItemId == nil)
        let other = try store.createProject(
            name: "独立", goal: "g", kindRaw: "", stageRaw: "", currentFocus: "", now: now
        )
        try store.savePracticeItem(id: blank.id, durationSeconds: 30, note: "", now: date(2026, 8, 28, 11, calendar: cal))
        #expect(throws: StoreError.invalidInput) {
            try store.setProjectStageVersion(projectId: other.id, itemId: blank.id, now: now)
        }
    }

    @Test func endedProjectCanSetVersionAndCreateTodayDoesNot() throws {
        let (store, repo, _) = makeStore()
        store.prepare()
        let cal = shanghai()
        let now = date(2026, 8, 28, calendar: cal)
        let project = try store.createProject(
            name: "知足", goal: "完整弹唱", kindRaw: "", stageRaw: "", currentFocus: "", now: now
        )
        let item = try store.createTodayPracticeItem(projectId: project.id, now: now, calendar: cal)
        try store.savePracticeItem(id: item.id, durationSeconds: 40, note: "", now: date(2026, 8, 28, 11, calendar: cal))
        try store.setProjectStatus(id: project.id, status: .completed, now: date(2026, 8, 28, 12, calendar: cal))
        try store.setProjectFinalVersion(
            projectId: project.id, itemId: item.id, now: date(2026, 8, 28, 13, calendar: cal)
        )
        #expect(try repo.project(id: project.id, profileId: item.profileId)?.finalVersionItemId == item.id)
        #expect(try repo.project(id: project.id, profileId: item.profileId)?.stageVersionItemId == nil)
    }

    @Test func deletingOrMovingItemClearsVersionRefs() throws {
        let (store, repo, _) = makeStore()
        store.prepare()
        let cal = shanghai()
        let now = date(2026, 8, 28, calendar: cal)
        let project = try store.createProject(
            name: "知足", goal: "完整弹唱", kindRaw: "", stageRaw: "", currentFocus: "", now: now
        )
        let item = try store.createTodayPracticeItem(projectId: project.id, now: now, calendar: cal)
        try store.savePracticeItem(id: item.id, durationSeconds: 50, note: "", now: date(2026, 8, 28, 11, calendar: cal))
        try store.setProjectStageVersion(projectId: project.id, itemId: item.id, now: date(2026, 8, 28, 12, calendar: cal))
        try store.setProjectFinalVersion(projectId: project.id, itemId: item.id, now: date(2026, 8, 28, 12, calendar: cal))
        try store.softDeletePracticeItem(id: item.id, now: date(2026, 8, 28, 13, calendar: cal))
        #expect(try repo.project(id: project.id, profileId: item.profileId)?.stageVersionItemId == nil)
        #expect(try repo.project(id: project.id, profileId: item.profileId)?.finalVersionItemId == nil)
        #expect(try repo.practiceItem(id: item.id, profileId: item.profileId) == nil)

        let live = try store.createTodayPracticeItem(
            projectId: project.id, now: date(2026, 8, 28, 14, calendar: cal), calendar: cal
        )
        try store.savePracticeItem(id: live.id, durationSeconds: 20, note: "n", now: date(2026, 8, 28, 15, calendar: cal))
        try store.setProjectStageVersion(projectId: project.id, itemId: live.id, now: date(2026, 8, 28, 16, calendar: cal))
        let other = try store.createProject(
            name: "另一首", goal: "g", kindRaw: "", stageRaw: "", currentFocus: "", now: now
        )
        try store.setPracticeItemProject(id: live.id, projectId: other.id, now: date(2026, 8, 28, 17, calendar: cal))
        #expect(try repo.project(id: project.id, profileId: live.profileId)?.stageVersionItemId == nil)
        #expect(try repo.project(id: other.id, profileId: live.profileId)?.stageVersionItemId == nil)
        #expect(try repo.practiceItem(id: live.id, profileId: live.profileId)?.projectId == other.id)
        #expect(try repo.practiceItem(id: live.id, profileId: live.profileId)?.practiceDayKey == "2026-08-28")
    }

    @Test func deleteProjectLeavesVersionIdsOnTombstone() throws {
        let (store, repo, _) = makeStore()
        store.prepare()
        let cal = shanghai()
        let now = date(2026, 8, 28, calendar: cal)
        let project = try store.createProject(
            name: "知足", goal: "完整弹唱", kindRaw: "", stageRaw: "", currentFocus: "", now: now
        )
        let item = try store.createTodayPracticeItem(projectId: project.id, now: now, calendar: cal)
        try store.savePracticeItem(id: item.id, durationSeconds: 30, note: "", now: date(2026, 8, 28, 11, calendar: cal))
        try store.setProjectStageVersion(projectId: project.id, itemId: item.id, now: date(2026, 8, 28, 12, calendar: cal))
        try store.deleteProject(id: project.id, now: date(2026, 8, 28, 13, calendar: cal))
        let tombstone = try #require(try repo.projectsIncludingDeleted().first { $0.id == project.id })
        #expect(tombstone.deletedAt != nil)
        #expect(tombstone.stageVersionItemId == item.id)
        #expect(try repo.practiceItem(id: item.id, profileId: item.profileId)?.projectId == nil)
    }
}
