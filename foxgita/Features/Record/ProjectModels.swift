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

    var practiceTitle: String {
        let focus = currentFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        return focus.isEmpty ? name : focus
    }
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
