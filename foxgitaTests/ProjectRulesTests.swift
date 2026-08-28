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
        currentFocus: String = "副歌节奏"
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
            isDeleted: isDeleted
        )
    }

    private func item(
        projectId: UUID?,
        dayKey: String,
        createdAt: Date,
        durationSeconds: Int,
        isDeleted: Bool = false
    ) -> PracticeItemSnapshot {
        PracticeItemSnapshot(
            id: UUID(),
            practiceDayKey: dayKey,
            createdAt: createdAt,
            title: "练",
            durationSeconds: durationSeconds,
            isDeleted: isDeleted,
            projectId: projectId
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
        let projects = [ProjectSnapshot(id: id, profileId: UUID(), name: "知足", goal: "g", kindRaw: "", stageRaw: "", currentFocus: "", status: .active, createdAt: Date(), isDeleted: false)]
        #expect(ProjectRules.projectName(id: id, in: projects) == "知足")
        #expect(ProjectRules.projectName(id: UUID(), in: projects) == nil)
    }
}
