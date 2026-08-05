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
}
