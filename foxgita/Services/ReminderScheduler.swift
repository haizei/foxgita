//
//  ReminderScheduler.swift
//  foxgita
//

import Foundation
import UserNotifications

/// Routes a reminder tap into the app. Kept separate from `AppRouter` so the
/// router stays free of UserNotifications.
final class ReminderDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let onOpen: @MainActor (UUID?) -> Void

    init(onOpen: @escaping @MainActor (UUID?) -> Void) {
        self.onOpen = onOpen
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        if identifier == ReminderScheduler.identifier {
            onOpen(nil)
        } else if let itemId = CountdownReminderScheduler.itemId(from: identifier) {
            onOpen(itemId)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

enum CountdownReminderScheduler {
    private static let prefix = "gita.countdown."

    static func identifier(itemId: UUID) -> String { prefix + itemId.uuidString }

    static func itemId(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
    }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func schedule(itemId: UUID, title: String, after seconds: Int) async {
        let center = UNUserNotificationCenter.current()
        let identifier = identifier(itemId: itemId)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let content = UNMutableNotificationContent()
        content.title = String(localized: "倒计时已完成")
        content.body = String(localized: "\(title) 的练习时间到了。")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(1, seconds)), repeats: false
        )
        try? await center.add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )
    }

    static func cancel(itemId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(itemId: itemId)]
        )
    }
}

enum ReminderScheduler {
    static let identifier = "gita.daily.reminder"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func schedule(hour: Int, minute: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "今天只练一点点")
        content.body = String(localized: "花几分钟摸摸琴，连续记录就不会断。")
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        try? await center.add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
