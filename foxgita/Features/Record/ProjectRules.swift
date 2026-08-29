import Foundation

enum ProjectStatus: String, Equatable {
    case active, completed, archived
}

struct ProjectSnapshot: Equatable, Identifiable {
    let id: UUID
    let profileId: UUID
    let name: String
    let goal: String
    let kindRaw: String
    let stageRaw: String
    let currentFocus: String
    let status: ProjectStatus
    let createdAt: Date
    let isDeleted: Bool
    let stageVersionItemId: UUID?
    let finalVersionItemId: UUID?
}

struct ProjectListState: Equatable {
    var current: ProjectSnapshot?
    var others: [ProjectSnapshot]
    var ended: [ProjectSnapshot]
}

enum ProjectVersionSlot: Equatable {
    case empty
    case resolved(PracticeItemSnapshot)
    case stale
}

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
        let focus = project.currentFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        return focus.isEmpty ? project.name : focus
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
