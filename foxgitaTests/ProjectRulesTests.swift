import Foundation
import Testing
@testable import foxgita

struct ProjectRulesTests {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal.date(from: DateComponents(timeZone: cal.timeZone, year: y, month: m, day: d, hour: h))!
    }

    private func project(
        id: UUID = UUID(),
        name: String = "知足",
        status: ProjectStatus = .active,
        createdAt: Date,
        isDeleted: Bool = false,
        currentFocus: String = "副歌节奏",
        stageVersionItemId: UUID? = nil,
        finalVersionItemId: UUID? = nil
    ) -> ProjectSnapshot {
        ProjectSnapshot(
            id: id,
            profileId: UUID(),
            name: name,
            goal: "能完整弹唱",
            kindRaw: "",
            stageRaw: "",
            currentFocus: currentFocus,
            status: status,
            createdAt: createdAt,
            isDeleted: isDeleted,
            stageVersionItemId: stageVersionItemId,
            finalVersionItemId: finalVersionItemId
        )
    }

    private func item(
        id: UUID = UUID(),
        projectId: UUID?,
        dayKey: String,
        createdAt: Date,
        durationSeconds: Int,
        isDeleted: Bool = false,
        note: String = "",
        recordingCount: Int = 0,
        title: String = "练",
        subtitle: String = "",
        recordings: [PracticeRecordingClip] = []
    ) -> PracticeItemSnapshot {
        PracticeItemSnapshot(
            id: id,
            practiceDayKey: dayKey,
            createdAt: createdAt,
            title: title,
            durationSeconds: durationSeconds,
            isDeleted: isDeleted,
            projectId: projectId,
            note: note,
            recordingCount: recordingCount,
            subtitle: subtitle,
            recordings: recordings
        )
    }

    private func clip(
        fileName: String,
        duration: Int,
        createdAt: Date
    ) -> PracticeRecordingClip {
        PracticeRecordingClip(
            id: UUID().uuidString,
            fileName: fileName,
            durationSec: duration,
            createdAt: createdAt
        )
    }

    @Test func snapshotProjectIdDefaultsNilAndDoesNotChangeEffectiveness() {
        let t0 = date(2026, 8, 16)
        let snap = PracticeItemSnapshot(
            id: UUID(),
            practiceDayKey: "2026-08-16",
            createdAt: t0,
            title: "独立",
            durationSeconds: 60,
            isDeleted: false
        )
        #expect(snap.projectId == nil)
        #expect(PracticeItemRules.isEffective(snap))
    }

    @Test func currentProjectPrefersLivePinThenRecentEffectiveThenNewestActive() {
        let pin = UUID()
        let recent = UUID()
        let newest = UUID()
        let t0 = date(2026, 8, 20)
        let t1 = date(2026, 8, 21)
        let t2 = date(2026, 8, 22)
        let projects = [
            project(id: pin, createdAt: t0),
            project(id: recent, name: "最近练", createdAt: t1),
            project(id: newest, name: "最新建", createdAt: t2),
        ]
        let items = [
            item(projectId: recent, dayKey: "2026-08-21", createdAt: t1, durationSeconds: 60),
        ]
        #expect(ProjectRules.currentProjectId(projects: projects, items: items, pinnedProjectId: pin) == pin)
        #expect(ProjectRules.currentProjectId(projects: projects, items: items, pinnedProjectId: nil) == recent)

        let completedPin = project(id: pin, status: .completed, createdAt: t0)
        #expect(
            ProjectRules.currentProjectId(projects: [completedPin, projects[1], projects[2]], items: items, pinnedProjectId: pin)
                == recent
        )

        let noItems = [project(id: newest, createdAt: t2), project(id: pin, createdAt: t0)]
        #expect(ProjectRules.currentProjectId(projects: noItems, items: [], pinnedProjectId: nil) == newest)
    }

    @Test func listStateSplitsCurrentOthersAndEnded() {
        let currentId = UUID()
        let otherId = UUID()
        let doneId = UUID()
        let archivedId = UUID()
        let t0 = date(2026, 8, 20)
        let projects = [
            project(id: currentId, createdAt: t0),
            project(id: otherId, name: "其他", createdAt: t0),
            project(id: doneId, name: "完成", status: .completed, createdAt: t0),
            project(id: archivedId, name: "暂不", status: .archived, createdAt: t0),
        ]
        let state = ProjectRules.listState(projects: projects, items: [], pinnedProjectId: currentId)
        #expect(state.current?.id == currentId)
        #expect(state.others.map(\.id) == [otherId])
        #expect(Set(state.ended.map(\.id)) == Set([doneId, archivedId]))
    }

    @Test func titleUsesTrimmedFocusOrName() {
        let withFocus = project(createdAt: date(2026, 8, 20), currentFocus: "  副歌  ")
        let emptyFocus = project(createdAt: date(2026, 8, 20), currentFocus: "   ")
        #expect(ProjectRules.titleForNewPracticeItem(withFocus) == "副歌")
        #expect(ProjectRules.titleForNewPracticeItem(emptyFocus) == "知足")
    }

    @Test func totalsAndEvidenceIgnoreOtherProjectsAndIneffectiveItems() {
        let pid = UUID()
        let t0 = date(2026, 8, 25, 9)
        let t1 = date(2026, 8, 26, 9)
        let items = [
            item(projectId: pid, dayKey: "2026-08-25", createdAt: t0, durationSeconds: 60),
            item(projectId: pid, dayKey: "2026-08-26", createdAt: t1, durationSeconds: 120),
            item(projectId: pid, dayKey: "2026-08-24", createdAt: date(2026, 8, 24), durationSeconds: 0),
            item(projectId: UUID(), dayKey: "2026-08-26", createdAt: t1, durationSeconds: 999),
            item(projectId: pid, dayKey: "2026-08-23", createdAt: date(2026, 8, 23), durationSeconds: 30, isDeleted: true),
        ]
        #expect(ProjectRules.totalSeconds(projectId: pid, in: items) == 180)
        #expect(ProjectRules.lastEvidence(projectId: pid, in: items)?.practiceDayKey == "2026-08-26")
        #expect(RecordMinutes.display(fromSeconds: 180) == 3)
    }

    @Test func projectNameForTagIsNilWhenMissing() {
        let id = UUID()
        let projects = [ProjectSnapshot(id: id, profileId: UUID(), name: "知足", goal: "g", kindRaw: "", stageRaw: "", currentFocus: "", status: .active, createdAt: Date(), isDeleted: false, stageVersionItemId: nil, finalVersionItemId: nil)]
        #expect(ProjectRules.projectName(id: id, in: projects) == "知足")
        #expect(ProjectRules.projectName(id: UUID(), in: projects) == nil)
    }

    @Test func lastEvidenceNilWhenOnlyIneffectiveItems() {
        let pid = UUID()
        let items = [
            PracticeItemSnapshot(id: UUID(), practiceDayKey: "2026-08-28", createdAt: Date(), title: "空", durationSeconds: 0, isDeleted: false, projectId: pid)
        ]
        #expect(ProjectRules.lastEvidence(projectId: pid, in: items) == nil)
        #expect(ProjectRules.totalSeconds(projectId: pid, in: items) == 0)
    }

    @Test func versionSlotResolvedEvenWhenItemIsNoLongerEffective() {
        let projectId = UUID()
        let itemId = UUID()
        let t0 = date(2026, 8, 20)
        let items = [
            item(
                id: itemId,
                projectId: projectId,
                dayKey: "2026-08-20",
                createdAt: t0,
                durationSeconds: 0
            ),
        ]
        let slot = ProjectRules.versionSlot(itemId: itemId, projectId: projectId, in: items)
        guard case .resolved(let snap) = slot else {
            Issue.record("expected resolved"); return
        }
        #expect(snap.id == itemId)
        #expect(ProjectRules.showsVersionPill(itemId: itemId, projectId: projectId, in: items))
    }

    @Test func versionSlotStaleWhenItemMissingDeletedOrWrongProject() {
        let projectId = UUID()
        let other = UUID()
        let t0 = date(2026, 8, 20)
        let missing = ProjectRules.versionSlot(itemId: UUID(), projectId: projectId, in: [])
        #expect(missing == .stale)
        let deletedId = UUID()
        let deleted = [
            item(id: deletedId, projectId: projectId, dayKey: "2026-08-20", createdAt: t0, durationSeconds: 60, isDeleted: true),
        ]
        #expect(ProjectRules.versionSlot(itemId: deletedId, projectId: projectId, in: deleted) == .stale)
        #expect(!ProjectRules.showsVersionPill(itemId: deletedId, projectId: projectId, in: deleted))
        let movedId = UUID()
        let moved = [
            item(id: movedId, projectId: other, dayKey: "2026-08-20", createdAt: t0, durationSeconds: 60),
        ]
        #expect(ProjectRules.versionSlot(itemId: movedId, projectId: projectId, in: moved) == .stale)
        #expect(ProjectRules.versionSlot(itemId: nil, projectId: projectId, in: moved) == .empty)
        #expect(!ProjectRules.showsVersionPill(itemId: nil, projectId: projectId, in: moved))
    }

    @Test func versionCandidatesAreEffectiveNewestFirstAndIncludeNoteOnly() {
        let projectId = UUID()
        let older = date(2026, 8, 20, 10)
        let newer = date(2026, 8, 21, 10)
        let olderId = UUID()
        let noteOnly = UUID()
        let withDuration = UUID()
        let blank = UUID()
        let otherProject = UUID()
        let items = [
            item(id: olderId, projectId: projectId, dayKey: "2026-08-21", createdAt: older, durationSeconds: 60),
            item(id: withDuration, projectId: projectId, dayKey: "2026-08-20", createdAt: newer, durationSeconds: 30),
            item(id: noteOnly, projectId: projectId, dayKey: "2026-08-19", createdAt: date(2026, 8, 22), durationSeconds: 0, note: "副歌抢拍"),
            item(id: blank, projectId: projectId, dayKey: "2026-08-28", createdAt: date(2026, 8, 28), durationSeconds: 0),
            item(id: otherProject, projectId: UUID(), dayKey: "2026-08-28", createdAt: date(2026, 8, 28), durationSeconds: 90),
        ]
        let candidates = ProjectRules.versionCandidates(projectId: projectId, in: items)
        #expect(candidates.map(\.id) == [noteOnly, withDuration, olderId])
    }

    @Test func showsThisTimeCardWhenActiveOrEndedWithFocus() {
        let t0 = date(2026, 8, 20)
        #expect(ProjectRules.showsThisTimeCard(project(status: .active, createdAt: t0, currentFocus: "")))
        #expect(ProjectRules.showsThisTimeCard(project(status: .completed, createdAt: t0, currentFocus: "副歌节奏")))
        #expect(!ProjectRules.showsThisTimeCard(project(status: .completed, createdAt: t0, currentFocus: "")))
        #expect(!ProjectRules.showsThisTimeCard(project(status: .archived, createdAt: t0, currentFocus: "  ")))
    }

    @Test func stateHandoffStageNotStartedWhenNoTodayPractice() {
        let pid = UUID()
        let todayKey = "2026-08-27"
        let yesterdayKey = "2026-08-26"
        let tYesterday = date(2026, 8, 26, 15)
        let items = [
            item(projectId: pid, dayKey: yesterdayKey, createdAt: tYesterday, durationSeconds: 600)
        ]
        let stage = ProjectRules.stateHandoffStage(
            projectId: pid,
            todayKey: todayKey,
            in: items,
            completedItemIds: []
        )
        #expect(stage == .notStarted)
    }

    @Test func stateHandoffStageCreatedWhenTodayItemExistsAndNotCompleted() {
        let pid = UUID()
        let todayKey = "2026-08-27"
        let todayId = UUID()
        let tToday = date(2026, 8, 27, 9)
        let items = [
            item(id: todayId, projectId: pid, dayKey: todayKey, createdAt: tToday, durationSeconds: 0)
        ]
        let stage = ProjectRules.stateHandoffStage(
            projectId: pid,
            todayKey: todayKey,
            in: items,
            completedItemIds: []
        )
        guard case .created(let snap) = stage else {
            Issue.record("Expected .created"); return
        }
        #expect(snap.id == todayId)
    }

    @Test func stateHandoffStageCompletedWhenTodayItemCompleted() {
        let pid = UUID()
        let todayKey = "2026-08-27"
        let todayId = UUID()
        let tToday = date(2026, 8, 27, 13)
        let items = [
            item(id: todayId, projectId: pid, dayKey: todayKey, createdAt: tToday, durationSeconds: 600)
        ]
        let stage = ProjectRules.stateHandoffStage(
            projectId: pid,
            todayKey: todayKey,
            in: items,
            completedItemIds: [todayId]
        )
        guard case .completed(let snap) = stage else {
            Issue.record("Expected .completed"); return
        }
        #expect(snap.id == todayId)
    }

    @Test func stateHandoffInfoLabelsAndEvidence() {
        let pid = UUID()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = date(2026, 8, 27, 18)
        let todayKey = "2026-08-27"
        let p = project(id: pid, name: "学会《知足》", createdAt: date(2026, 8, 20), currentFocus: "主歌进入副歌时保持节奏")

        // 1. Not started: last evidence is yesterday
        let tYesterday = date(2026, 8, 26, 15)
        let yesterdayItem = item(projectId: pid, dayKey: "2026-08-26", createdAt: tYesterday, durationSeconds: 1080, note: "有录音", recordingCount: 1)
        let info1 = ProjectRules.stateHandoffInfo(
            project: p,
            todayKey: todayKey,
            in: [yesterdayItem],
            completedItemIds: [],
            now: now,
            calendar: cal
        )
        #expect(info1.focusLabel == "这次")
        #expect(info1.focusTitle == "主歌进入副歌时保持节奏")
        #expect(info1.buttonLabel == "开始今天的练习")
        #expect(info1.lastEvidenceText == "上次 · 昨天")
        #expect(info1.lastEvidencePracticeTitle == "练 · 18 分钟 · 有录音")

        // 2. Created today: last evidence remains yesterday, button is 继续这次练习
        let todayId = UUID()
        let tToday = date(2026, 8, 27, 9)
        let todayItem = item(id: todayId, projectId: pid, dayKey: todayKey, createdAt: tToday, durationSeconds: 0)
        let info2 = ProjectRules.stateHandoffInfo(
            project: p,
            todayKey: todayKey,
            in: [todayItem, yesterdayItem],
            completedItemIds: [],
            now: now,
            calendar: cal
        )
        #expect(info2.focusLabel == "今天已创建 · 这次")
        #expect(info2.buttonLabel == "继续这次练习")
        #expect(info2.lastEvidenceText == "上次 · 昨天")

        // 3. Completed today: last evidence becomes today, button is 再练一次
        let completedTodayItem = item(id: todayId, projectId: pid, dayKey: todayKey, createdAt: tToday, durationSeconds: 720, recordingCount: 1)
        let info3 = ProjectRules.stateHandoffInfo(
            project: p,
            todayKey: todayKey,
            in: [completedTodayItem, yesterdayItem],
            completedItemIds: [todayId],
            now: now,
            calendar: cal
        )
        #expect(info3.focusLabel == "再练重点")
        #expect(info3.buttonLabel == "再练一次")
        #expect(info3.lastEvidenceText?.starts(with: "上次 · 今天") == true)
        #expect(info3.lastEvidencePracticeTitle == "练 · 12 分钟 · 有录音")
    }

    @Test func otherProjectContextIncludesFocusAndEvidence() {
        let pid = UUID()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = date(2026, 8, 27, 18)
        let p = project(id: pid, name: "和弦转换", createdAt: date(2026, 8, 20), currentFocus: "C 到 G 的转换要干净")
        let t = date(2026, 8, 26, 10)
        let practice = item(projectId: pid, dayKey: "2026-08-26", createdAt: t, durationSeconds: 60)

        let ctx = ProjectRules.otherProjectContext(
            project: p,
            in: [practice],
            now: now,
            calendar: cal
        )
        #expect(ctx == "这次：C 到 G 的转换要干净 · 昨天")
    }

    @Test func handoffCreatesWithFocusResumesBlankItemAndOpensAnotherAfterComplete() {
        let pid = UUID()
        let today = "2026-10-15"
        let blankId = UUID()
        let projectWithFocus = project(id: pid, name: "知足", createdAt: date(2026, 10, 1), currentFocus: "副歌节奏")
        let notStarted = ProjectPracticeStateHandoff.decide(
            project: projectWithFocus,
            todayKey: today,
            items: [],
            completedItemIds: []
        )
        #expect(notStarted.buttonLabel == "开始今天的练习")
        #expect(notStarted.action == .createNew(title: "副歌节奏"))

        let unnamed = project(id: pid, name: "知足", createdAt: date(2026, 10, 1), currentFocus: "  ")
        let fallback = ProjectPracticeStateHandoff.decide(
            project: unnamed,
            todayKey: today,
            items: [],
            completedItemIds: []
        )
        #expect(fallback.action == .createNew(title: "知足"))

        let blank = item(id: blankId, projectId: pid, dayKey: today, createdAt: date(2026, 10, 15, 9), durationSeconds: 0)
        let resume = ProjectPracticeStateHandoff.decide(
            project: projectWithFocus,
            todayKey: today,
            items: [blank],
            completedItemIds: []
        )
        #expect(resume.buttonLabel == "继续这次练习")
        #expect(resume.action == .resume(blankId))

        let again = ProjectPracticeStateHandoff.decide(
            project: projectWithFocus,
            todayKey: today,
            items: [blank],
            completedItemIds: [blankId]
        )
        #expect(again.buttonLabel == "再练一次")
        #expect(again.action == .createAnother(title: "副歌节奏", completedItemId: blankId))
    }

    @Test func progressStoryIsEmptyForNoPracticeAndQualitativeForScopedItems() {
        let pid = UUID()
        #expect(ProjectProgressStory.make(projectId: pid, items: []) == nil)

        let only = item(
            projectId: pid,
            dayKey: "2026-10-03",
            createdAt: date(2026, 10, 3),
            durationSeconds: 600,
            title: "小节慢练"
        )
        let single = ProjectProgressStory.make(projectId: pid, items: [only])
        #expect(single?.headline == "分段练")
        #expect(single?.milestones.count == 1)
        #expect(single?.milestones.first?.label == "小节慢练")
        #expect(single?.milestones.first?.dayKey == "2026-10-03")

        let items = [
            item(projectId: pid, dayKey: "2026-10-03", createdAt: date(2026, 10, 3), durationSeconds: 600, title: "副歌分段"),
            item(projectId: pid, dayKey: "2026-10-04", createdAt: date(2026, 10, 4), durationSeconds: 600, title: "还是分段"),
            item(projectId: pid, dayKey: "2026-10-08", createdAt: date(2026, 10, 8), durationSeconds: 600, note: "开始连贯", title: "串联"),
            item(projectId: pid, dayKey: "2026-10-13", createdAt: date(2026, 10, 13), durationSeconds: 600, title: "完整弹一遍"),
        ]
        let story = ProjectProgressStory.make(projectId: pid, items: items)
        #expect(story?.headline == "从分段练，到完整弹一遍")
        #expect(story?.milestones.map(\.label) == ["副歌分段", "串联", "完整弹一遍"])
        let rendered = [story?.headline ?? ""] + (story?.milestones.map(\.label) ?? [])
        #expect(rendered.allSatisfy { !$0.contains("%") && !$0.contains("评分") })
        #expect(ProjectProgressStory.disclaimer == "根据已记录的练习范围 · 非完成度评分")

        let sung = ProjectProgressStory.make(projectId: pid, items: [
            item(projectId: pid, dayKey: "2026-10-03", createdAt: date(2026, 10, 3), durationSeconds: 600, title: "分段"),
            item(projectId: pid, dayKey: "2026-10-08", createdAt: date(2026, 10, 8), durationSeconds: 600, title: "连贯弹唱"),
            item(projectId: pid, dayKey: "2026-10-13", createdAt: date(2026, 10, 13), durationSeconds: 600, title: "完整弹唱一遍"),
        ])
        #expect(sung?.milestones.compactMap(\.scope) == [.segmented, .connected, .complete])
        #expect(sung?.headline == "从分段练，到完整弹一遍")
    }

    @Test func lastEvidenceSkipsInvalidItemsAndHidesMissingRecording() {
        let pid = UUID()
        let early = date(2026, 10, 3, 11)
        let latest = date(2026, 10, 13, 18)
        let take = clip(fileName: "chorus.m4a", duration: 124, createdAt: latest)
        let items = [
            item(projectId: pid, dayKey: "2026-10-13", createdAt: date(2026, 10, 13, 19), durationSeconds: 0, title: "空的"),
            item(
                projectId: pid,
                dayKey: "2026-10-13",
                createdAt: latest,
                durationSeconds: 18 * 60,
                note: "副歌顺了一点",
                recordingCount: 1,
                title: "副歌",
                subtitle: "只练副歌",
                recordings: [take]
            ),
            item(projectId: pid, dayKey: "2026-10-03", createdAt: early, durationSeconds: 600, title: "更早"),
            item(projectId: pid, dayKey: "2026-10-14", createdAt: date(2026, 10, 14), durationSeconds: 600, isDeleted: true, title: "删了"),
        ]
        let evidence = LastPracticeEvidence.latest(projectId: pid, items: items)
        #expect(evidence?.title == "副歌")
        #expect(evidence?.content == "只练副歌")
        #expect(evidence?.reflection == "副歌顺了一点")
        #expect(evidence?.dateAndDuration == "10月13日 · 18分钟")
        #expect(evidence?.recording?.fileName == "chorus.m4a")
        #expect(evidence?.recordingLabel == "录音 02:04")

        let quiet = item(projectId: pid, dayKey: "2026-10-02", createdAt: date(2026, 10, 2), durationSeconds: 300, note: "只有字", title: "无录音")
        let textOnly = LastPracticeEvidence.latest(projectId: pid, items: [quiet])
        #expect(textOnly?.recording == nil)
        #expect(textOnly?.recordingLabel == nil)
        #expect(textOnly?.reflection == "只有字")
    }

    @Test func noteProjectionIsReverseChronologicalAndDropsEmptyNotes() {
        let pid = UUID()
        let other = UUID()
        let items = [
            item(projectId: pid, dayKey: "2026-10-01", createdAt: date(2026, 10, 1, 9), durationSeconds: 60, note: "最早"),
            item(projectId: pid, dayKey: "2026-10-12", createdAt: date(2026, 10, 12, 8), durationSeconds: 0, note: "   "),
            item(projectId: pid, dayKey: "2026-10-03", createdAt: date(2026, 10, 3, 9), durationSeconds: 60, note: "中间", recordingCount: 1),
            item(projectId: pid, dayKey: "2026-10-13", createdAt: date(2026, 10, 13, 9), durationSeconds: 60, note: "最新"),
            item(projectId: pid, dayKey: "2026-10-11", createdAt: date(2026, 10, 11, 9), durationSeconds: 60, isDeleted: true, note: "删掉"),
            item(projectId: other, dayKey: "2026-10-14", createdAt: date(2026, 10, 14, 9), durationSeconds: 60, note: "别人的"),
            item(projectId: pid, dayKey: "2026-10-02", createdAt: date(2026, 10, 2, 9), durationSeconds: 60, note: "第二条"),
        ]
        let notes = ProjectNoteProjection.entries(projectId: pid, items: items)
        #expect(notes.map(\.body) == ["最新", "中间", "第二条", "最早"])
        #expect(notes.first { $0.body == "中间" }?.hasRecording == true)
        #expect(notes.first { $0.body == "最新" }?.hasRecording == false)
        #expect(ProjectNoteProjection.preview(projectId: pid, items: items).map(\.body) == ["最新", "中间", "第二条"])
        #expect(ProjectNoteProjection.footer == "ⓘ 笔记来自每次练习，可在原练习记录中修改")
    }

    @Test func benchmarkUsesStageVersionThenEarliestAndRefusesASingleRecording() {
        let pid = UUID()
        let firstId = UUID()
        let stageId = UUID()
        let newestId = UUID()
        let firstAt = date(2026, 10, 3, 10)
        let stageAt = date(2026, 10, 8, 10)
        let newestAt = date(2026, 10, 13, 10)
        let items = [
            item(
                id: newestId, projectId: pid, dayKey: "2026-10-13", createdAt: newestAt, durationSeconds: 60,
                recordingCount: 1, title: "最近",
                recordings: [clip(fileName: "new.m4a", duration: 90, createdAt: newestAt)]
            ),
            item(
                id: stageId, projectId: pid, dayKey: "2026-10-08", createdAt: stageAt, durationSeconds: 60,
                recordingCount: 1, title: "阶段",
                recordings: [clip(fileName: "stage.m4a", duration: 80, createdAt: stageAt)]
            ),
            item(
                id: firstId, projectId: pid, dayKey: "2026-10-03", createdAt: firstAt, durationSeconds: 60,
                recordingCount: 1, title: "最初",
                recordings: [clip(fileName: "first.m4a", duration: 70, createdAt: firstAt)]
            ),
        ]
        guard case .ready(let explicitStage, let explicitRecent) = AudioBenchmarkVersion.resolve(
            stageVersionItemId: stageId, projectId: pid, items: items
        ) else {
            Issue.record("Expected explicit stage pair")
            return
        }
        #expect(explicitStage.itemId == stageId)
        #expect(explicitRecent.itemId == newestId)

        guard case .ready(let fallbackStage, let fallbackRecent) = AudioBenchmarkVersion.resolve(
            stageVersionItemId: nil, projectId: pid, items: items
        ) else {
            Issue.record("Expected earliest fallback")
            return
        }
        #expect(fallbackStage.itemId == firstId)
        #expect(fallbackRecent.itemId == newestId)
        #expect(AudioBenchmarkVersion.spanLine(stageDayKey: "2026-10-03", recentDayKey: "2026-10-13") == "10月3日 阶段版 → 10月13日 最近录音")

        let alone = [items[0]]
        #expect(AudioBenchmarkVersion.resolve(stageVersionItemId: nil, projectId: pid, items: alone) == .needsAnotherRecording)
        #expect(AudioBenchmarkVersion.resolve(stageVersionItemId: nil, projectId: pid, items: []) == .unavailable)

        let missingStage = AudioBenchmarkVersion.resolve(stageVersionItemId: UUID(), projectId: pid, items: items)
        guard case .ready(let fellBack, _) = missingStage else {
            Issue.record("Missing stage id should fall back to the earliest recording")
            return
        }
        #expect(fellBack.itemId == firstId)

        guard case .ready(let overridden, let other) = AudioBenchmarkVersion.resolve(
            stageVersionItemId: nil,
            projectId: pid,
            items: items,
            overrideStageItemId: newestId,
            overrideRecentItemId: stageId
        ) else {
            Issue.record("Override should stay in memory")
            return
        }
        #expect(overridden.itemId == newestId)
        #expect(other.itemId == stageId)
        #expect(AudioBenchmarkVersion.needsAnotherCopy == "再记录一次即可开启对照")
    }

    @Test func observationParsesClocksDegradesOfflineAndSeekFeedsTheHandoff() {
        let online = AIAudioObservationRules.observe(
            stageNote: "副歌在 00:42 停顿",
            recentNote: "00:38 就连贯了",
            stageDuration: 124,
            recentDuration: 90,
            audioAvailable: true
        )
        #expect(online.conclusion == "最近这一次更连贯，阶段版里还有明显停顿。")
        #expect(online.usesAudioTimestamps)
        #expect(online.stageCue.seconds == 42)
        #expect(online.recentCue.seconds == 38)
        #expect(online.stageCue.caption == "阶段版 00:42")
        #expect(online.recentCue.caption == "最近 00:38")
        #expect(!online.conclusion.contains("%"))

        let offline = AIAudioObservationRules.observe(
            stageNote: "这里有停顿",
            recentNote: "后面连贯了一些",
            stageDuration: 0,
            recentDuration: 0,
            audioAvailable: false
        )
        #expect(!offline.usesAudioTimestamps)
        #expect(offline.stageCue.seconds == nil)
        #expect(offline.recentCue.seconds == nil)
        #expect(!offline.conclusion.isEmpty)
        #expect(offline.conclusion.contains("停顿"))
        #expect(offline.conclusion.contains("连贯"))

        var playback = AudioComparisonPlayback()
        playback.seekAndPlay(.a, seconds: online.stageCue.seconds ?? -1, duration: 124)
        #expect(playback.playing == .a)
        #expect(playback.positionA == 42)

        let pid = UUID()
        let todayId = UUID()
        let decision = ProjectPracticeStateHandoff.decide(
            project: project(id: pid, createdAt: date(2026, 10, 1), currentFocus: "副歌"),
            todayKey: "2026-10-15",
            items: [item(id: todayId, projectId: pid, dayKey: "2026-10-15", createdAt: date(2026, 10, 15, 9), durationSeconds: 0)],
            completedItemIds: []
        )
        #expect(decision.buttonLabel == "继续这次练习")
        #expect(decision.action == .resume(todayId))
        #expect(ProjectNoteProjection.comparisonCitation(cited: 2, total: 5) == "本次对比引用 2 条 · 项目共 5 条")
    }
}
