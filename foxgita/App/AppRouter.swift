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
    var role: UserRole = .novice
    var isDark: Bool = false
    var displayName: String = "海仔"
}
