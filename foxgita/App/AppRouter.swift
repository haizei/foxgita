//
//  AppRouter.swift
//  foxgita
//

import Foundation
import Observation

enum MainTab: Hashable {
    case practice, record, history, settings
}

enum PracticeRoute: Hashable {
    case detail(taskId: String)
}

enum RecordRoute: Hashable {
    case detail(taskId: String)
}

@Observable
final class AppRouter {
    var selectedTab: MainTab = .practice
    var practicePath: [PracticeRoute] = []
    var recordPath: [RecordRoute] = []
    /// Raised when a reminder notification is tapped. `PracticeView` resolves it
    /// to today's first task, since only it holds the task query.
    var openTodayFirstPractice = false
    /// Raised after a successful (or empty) complete so PracticeView snaps back to today.
    var returnPracticeToToday = false
    /// Set by detail / past-day open; PracticeView shows it then clears.
    var practiceToast: String?
    /// Set only after an effective Complete. Never persist. Never infer "latest session".
    var lastCompletedSessionId: String?

    func clearJustCompleted() {
        lastCompletedSessionId = nil
    }
}
