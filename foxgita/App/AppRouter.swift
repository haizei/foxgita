//
//  AppRouter.swift
//  foxgita
//

import Foundation
import Observation

enum MainTab: Hashable {
    case practice, record, settings
}

enum RecordHomeSegment: Hashable {
    case practice, project
}

enum RecordHistorySegment: Hashable {
    case calendar, stats
}

enum PracticeRoute: Hashable {
    case detail(itemId: UUID)
}

enum RecordRoute: Hashable {
    case history(RecordHistorySegment)
    case practiceDetail(itemId: UUID)
    case projectCreate
    case projectCreateFromPractice(itemId: UUID)
    case projectDetail(projectId: UUID)
    case projectEdit(projectId: UUID)
    case projectTrajectory(projectId: UUID)
}

@Observable
final class AppRouter {
    var selectedTab: MainTab = .practice
    var practicePath: [PracticeRoute] = []
    var recordPath: [RecordRoute] = []
    var recordSegment: RecordHomeSegment = .practice
    var recordWeekStart: Date = StatsAggregator.week().start
    var recordFocusDayKey: String?
    /// Raised when a reminder notification is tapped. `PracticeView` resolves it
    /// to today's first task, since only it holds the task query.
    var openTodayFirstPractice = false
    /// Raised after a successful (or empty) complete so PracticeView snaps back to today.
    var returnPracticeToToday = false
    /// Set by detail / past-day open; PracticeView shows it then clears.
    var practiceToast: String?
    /// Set only after an effective Complete. Never persist.
    var lastCompletedPracticeItemId: UUID?

    func clearJustCompleted() {
        lastCompletedPracticeItemId = nil
    }

    func presentCreatedProject(_ projectId: UUID, fromPracticeTab: Bool) {
        recordSegment = .project
        if fromPracticeTab {
            selectedTab = .record
            practicePath.removeAll()
            recordPath = [.projectDetail(projectId: projectId)]
        } else {
            replaceLastRecordRoute(.projectDetail(projectId: projectId))
        }
    }

    func openRecord(dayKey: String?) {
        selectedTab = .record
        if let dayKey, !dayKey.isEmpty {
            recordFocusDayKey = dayKey
            recordPath = [.history(.calendar)]
        } else {
            recordFocusDayKey = nil
            recordPath = []
        }
    }

    func replaceLastRecordRoute(_ route: RecordRoute) {
        if recordPath.isEmpty {
            recordPath.append(route)
        } else {
            recordPath[recordPath.count - 1] = route
        }
    }

    /// Dismisses the stack that opened this detail. `fromRecord` is `openedFromRecord`.
    func dismissPracticeDetail(fromRecord: Bool) {
        if fromRecord {
            if case .practiceDetail = recordPath.last {
                recordPath.removeLast()
            }
            return
        }
        practicePath.removeAll()
    }
}
