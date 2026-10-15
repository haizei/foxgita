import Foundation

enum ProjectRules {
    static func snapshot(from project: Project) -> ProjectSnapshot {
        ProjectSnapshot(
            id: project.id,
            profileId: project.profileId,
            name: project.name,
            goal: project.goal,
            kindRaw: project.kindRaw,
            stageRaw: project.stageRaw,
            currentFocus: project.currentFocus,
            status: project.status,
            createdAt: project.createdAt,
            isDeleted: project.deletedAt != nil,
            stageVersionItemId: project.stageVersionItemId,
            finalVersionItemId: project.finalVersionItemId,
        )
    }

    static func currentProjectId(
        projects: [ProjectSnapshot],
        items: [PracticeItemSnapshot],
        pinnedProjectId: UUID?
    ) -> UUID? {
        let live = projects.filter { !$0.isDeleted && $0.status == .active }
        if let pinnedProjectId, live.contains(where: { $0.id == pinnedProjectId }) {
            return pinnedProjectId
        }
        let effective = items.filter { PracticeItemRules.isEffective($0) && $0.projectId != nil }
        let newestPractice = effective.max { $0.createdAt < $1.createdAt }
        if let pid = newestPractice?.projectId, live.contains(where: { $0.id == pid }) {
            return pid
        }
        return live.max { $0.createdAt < $1.createdAt }?.id
    }

    static func listState(
        projects: [ProjectSnapshot],
        items: [PracticeItemSnapshot],
        pinnedProjectId: UUID?
    ) -> ProjectListState {
        let visible = projects.filter { !$0.isDeleted }
        let currentId = currentProjectId(projects: visible, items: items, pinnedProjectId: pinnedProjectId)
        let current = visible.first { $0.id == currentId && $0.status == .active }
        let others = visible
            .filter { $0.status == .active && $0.id != currentId }
            .sorted { sortKey($0, items: items) > sortKey($1, items: items) }
        let ended = visible.filter { $0.status == .completed || $0.status == .archived }
        return ProjectListState(current: current, others: others, ended: ended)
    }

    static func titleForNewPracticeItem(_ project: ProjectSnapshot) -> String {
        project.practiceTitle
    }

    static func associatedEffectiveItems(projectId: UUID, in items: [PracticeItemSnapshot]) -> [PracticeItemSnapshot] {
        items
            .filter { $0.projectId == projectId && PracticeItemRules.isEffective($0) }
            .sorted {
                if $0.practiceDayKey != $1.practiceDayKey { return $0.practiceDayKey > $1.practiceDayKey }
                return $0.createdAt > $1.createdAt
            }
    }

    static func totalSeconds(projectId: UUID, in items: [PracticeItemSnapshot]) -> Int {
        associatedEffectiveItems(projectId: projectId, in: items).reduce(0) { $0 + max(0, $1.durationSeconds) }
    }

    static func lastEvidence(projectId: UUID, in items: [PracticeItemSnapshot]) -> PracticeItemSnapshot? {
        associatedEffectiveItems(projectId: projectId, in: items).first
    }

    static func projectName(id: UUID, in projects: [ProjectSnapshot]) -> String? {
        guard let project = projects.first(where: { $0.id == id }), !project.isDeleted else { return nil }
        return project.name
    }

    static func versionSlot(
        itemId: UUID?,
        projectId: UUID,
        in items: [PracticeItemSnapshot]
    ) -> ProjectVersionSlot {
        guard let itemId else { return .empty }
        guard let item = items.first(where: { $0.id == itemId }) else { return .stale }
        guard !item.isDeleted, item.projectId == projectId else { return .stale }
        return .resolved(item)
    }

    static func showsVersionPill(
        itemId: UUID?,
        projectId: UUID,
        in items: [PracticeItemSnapshot]
    ) -> Bool {
        if case .resolved = versionSlot(itemId: itemId, projectId: projectId, in: items) {
            return true
        }
        return false
    }

    static func versionCandidates(projectId: UUID, in items: [PracticeItemSnapshot]) -> [PracticeItemSnapshot] {
        items
            .filter { $0.projectId == projectId && PracticeItemRules.isEffective($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func showsThisTimeCard(_ project: ProjectSnapshot) -> Bool {
        if project.status == .active { return true }
        let focus = project.currentFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        return !focus.isEmpty
    }

    // MARK: - State Handoff

    enum StateHandoffStage: Equatable {
        /// 01 · 今天尚未开始：今日尚无该项目的练习项
        case notStarted
        /// 02 · 今日已创建：今日已有该项目的练习项，且该项处于进行中（未点完成）
        case created(PracticeItemSnapshot)
        /// 03 · 今天已完成：今日该项目的练习项已明确完成，再次练习将创建新条目
        case completed(PracticeItemSnapshot)
    }

    struct StateHandoffInfo: Equatable {
        let stage: StateHandoffStage
        let focusLabel: String
        let focusTitle: String
        let buttonLabel: String
        let lastEvidenceText: String?
        let lastEvidencePracticeTitle: String?
    }

    static func stateHandoffStage(
        projectId: UUID,
        todayKey: String,
        in items: [PracticeItemSnapshot],
        completedItemIds: Set<UUID>
    ) -> StateHandoffStage {
        switch ProjectPracticeStateHandoff.stage(
            projectId: projectId,
            todayKey: todayKey,
            in: items,
            completedItemIds: completedItemIds
        ) {
        case .notStarted:
            return .notStarted
        case .resume(let item):
            return .created(item)
        case .createAnother(let item):
            return .completed(item)
        }
    }

    static func stateHandoffInfo(
        project: ProjectSnapshot,
        todayKey: String,
        in items: [PracticeItemSnapshot],
        completedItemIds: Set<UUID>,
        now: Date,
        calendar: Calendar
    ) -> StateHandoffInfo {
        let stage = stateHandoffStage(
            projectId: project.id,
            todayKey: todayKey,
            in: items,
            completedItemIds: completedItemIds
        )

        let trimmedFocus = project.currentFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusTitle = trimmedFocus.isEmpty ? project.name : trimmedFocus

        let focusLabel: String
        let buttonLabel: String
        let evidenceItem: PracticeItemSnapshot?

        switch stage {
        case .notStarted:
            focusLabel = String(localized: "这次")
            buttonLabel = String(localized: "开始今天的练习")
            evidenceItem = lastEvidence(projectId: project.id, in: items)
        case .created:
            focusLabel = String(localized: "今天已创建 · 这次")
            buttonLabel = String(localized: "继续这次练习")
            let pastEffective = associatedEffectiveItems(projectId: project.id, in: items)
                .filter { $0.practiceDayKey != todayKey }
            evidenceItem = pastEffective.first
        case .completed:
            focusLabel = String(localized: "再练重点")
            buttonLabel = String(localized: "再练一次")
            evidenceItem = lastEvidence(projectId: project.id, in: items)
        }

        let lastEvidenceText: String?
        let lastEvidencePracticeTitle: String?

        if let evidence = evidenceItem {
            let dayText = formatEvidenceDay(evidence.practiceDayKey, createdAt: evidence.createdAt, now: now, calendar: calendar)
            lastEvidenceText = "上次 · \(dayText)"
            let durationMin = RecordMinutes.display(fromSeconds: evidence.durationSeconds)
            let mediaText = evidence.recordingCount > 0 ? " · 有录音" : ""
            lastEvidencePracticeTitle = "\(evidence.title) · \(durationMin) 分钟\(mediaText)"
        } else {
            lastEvidenceText = nil
            lastEvidencePracticeTitle = nil
        }

        return StateHandoffInfo(
            stage: stage,
            focusLabel: focusLabel,
            focusTitle: focusTitle,
            buttonLabel: buttonLabel,
            lastEvidenceText: lastEvidenceText,
            lastEvidencePracticeTitle: lastEvidencePracticeTitle
        )
    }

    private static func formatEvidenceDay(
        _ dayKey: String,
        createdAt: Date,
        now: Date,
        calendar: Calendar
    ) -> String {
        let todayKey = PracticeDayKey.make(from: now, calendar: calendar)
        if dayKey == todayKey {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.dateFormat = "HH:mm"
            return "今天 \(formatter.string(from: createdAt))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) {
            if dayKey == PracticeDayKey.make(from: yesterday, calendar: calendar) {
                return "昨天"
            }
        }
        guard let date = RecordTimelineRules.date(fromDayKey: dayKey, calendar: calendar) else {
            return dayKey
        }
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return "\(m) 月 \(d) 日"
    }

    static func otherProjectContext(
        project: ProjectSnapshot,
        in items: [PracticeItemSnapshot],
        now: Date,
        calendar: Calendar
    ) -> String {
        let focus = project.currentFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusPrefix = focus.isEmpty ? "" : "这次：\(focus) · "

        if let evidence = lastEvidence(projectId: project.id, in: items) {
            let dayText = formatEvidenceDay(evidence.practiceDayKey, createdAt: evidence.createdAt, now: now, calendar: calendar)
            return "\(focusPrefix)\(dayText)"
        }
        if !focus.isEmpty {
            return "这次：\(focus)"
        }
        return String(localized: "还没练习")
    }

    private static func hasEffectiveActivity(_ project: ProjectSnapshot, items: [PracticeItemSnapshot]) -> Bool {
        !associatedEffectiveItems(projectId: project.id, in: items).isEmpty
    }

    private static func lastActivity(_ project: ProjectSnapshot, items: [PracticeItemSnapshot]) -> Date {
        associatedEffectiveItems(projectId: project.id, in: items).first?.createdAt ?? project.createdAt
    }

    private static func sortKey(_ project: ProjectSnapshot, items: [PracticeItemSnapshot]) -> (Int, Date) {
        let hasActivity = hasEffectiveActivity(project, items: items)
        return (hasActivity ? 1 : 0, lastActivity(project, items: items))
    }
}
