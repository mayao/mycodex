import Foundation
import UserNotifications
import VitalCommandMobileCore

enum LocalNotificationManager {
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard settings.authorizationStatus == .notDetermined else {
            return
        }

        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func notify(title: String, body: String) async {
        await requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Plan Reminders

    /// Schedule a daily reminder for a plan item at the given time hint.
    /// Identifier format: "plan-reminder-{planItemId}" for easy cancellation.
    static func schedulePlanReminder(planItem: HealthPlanItem) async {
        await requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "健康计划提醒"
        content.body = "\(planItem.dimension.icon) \(planItem.title)"
        content.sound = .default
        content.categoryIdentifier = "HEALTH_PLAN_REMINDER"

        // Parse time hint to determine trigger time
        let (hour, minute) = parseTimeHint(planItem.timeHint)

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger: UNNotificationTrigger
        switch planItem.frequency {
        case .daily:
            // Repeat daily at the specified time
            trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        case .weekly:
            // Repeat weekly on the same weekday as creation
            if let createdDate = ISO8601DateFormatter().date(from: planItem.createdAt) {
                dateComponents.weekday = Calendar.current.component(.weekday, from: createdDate)
            }
            trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        case .once:
            // Fire once tomorrow at the specified time
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            dateComponents.year = Calendar.current.component(.year, from: tomorrow)
            dateComponents.month = Calendar.current.component(.month, from: tomorrow)
            dateComponents.day = Calendar.current.component(.day, from: tomorrow)
            trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        }

        let request = UNNotificationRequest(
            identifier: "plan-reminder-\(planItem.id)",
            content: content,
            trigger: trigger
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Cancel all reminders for a specific plan item.
    static func cancelPlanReminders(planItemId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["plan-reminder-\(planItemId)"]
        )
    }

    /// Schedule a daily "evening check" at 20:00 to remind about unfinished plan items.
    static func scheduleDailyCheckReminder() async {
        await requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "今日计划回顾"
        content.body = "看看今天的健康计划完成得怎么样？"
        content.sound = .default
        content.categoryIdentifier = "HEALTH_PLAN_DAILY_CHECK"

        var dateComponents = DateComponents()
        dateComponents.hour = 20
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "plan-daily-check",
            content: content,
            trigger: trigger
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Cancel the daily check reminder.
    static func cancelDailyCheckReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["plan-daily-check"]
        )
    }

    // MARK: - Helpers

    /// Parse time hint string like "07:00", "morning", "evening" into (hour, minute).
    private static func parseTimeHint(_ hint: String?) -> (Int, Int) {
        guard let hint = hint, !hint.isEmpty else {
            return (9, 0) // Default 9:00 AM
        }

        // Try "HH:mm" format
        let parts = hint.split(separator: ":")
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
            return (h, m)
        }

        // Named hints
        switch hint.lowercased() {
        case "morning": return (7, 30)
        case "afternoon": return (14, 0)
        case "evening": return (19, 0)
        case "night": return (21, 0)
        default: return (9, 0)
        }
    }
}
