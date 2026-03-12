import EventKit
import VitalCommandMobileCore

enum CalendarIntegration {
    private static let store = EKEventStore()

    /// Request calendar access (iOS 17+).
    static func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await store.requestFullAccessToEvents()
            } catch {
                print("[Calendar] Access request failed: \(error.localizedDescription)")
                return false
            }
        } else {
            do {
                return try await store.requestAccess(to: .event)
            } catch {
                return false
            }
        }
    }

    /// Check if we have calendar access.
    static var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    /// Create a calendar event for a plan item.
    /// Returns the event identifier for later removal.
    @discardableResult
    static func createEvent(for planItem: HealthPlanItem) async -> String? {
        guard await requestAccess() else { return nil }

        let event = EKEvent(eventStore: store)
        event.title = "🏥 \(planItem.title)"
        event.notes = planItem.description
        event.calendar = store.defaultCalendarForNewEvents

        // Set start time based on time hint
        let (hour, minute) = parseTimeHint(planItem.timeHint)
        var startComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        startComponents.hour = hour
        startComponents.minute = minute

        guard let startDate = Calendar.current.date(from: startComponents) else { return nil }

        // If the time has passed today, set it for tomorrow
        let actualStart = startDate < Date()
            ? Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
            : startDate

        event.startDate = actualStart
        event.endDate = Calendar.current.date(byAdding: .minute, value: 30, to: actualStart) ?? actualStart

        // Add an alarm 10 minutes before
        event.addAlarm(EKAlarm(relativeOffset: -600))

        // Set recurrence based on frequency
        switch planItem.frequency {
        case .daily:
            event.recurrenceRules = [EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: 1,
                end: nil
            )]
        case .weekly:
            event.recurrenceRules = [EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                end: nil
            )]
        case .once:
            break // No recurrence
        }

        do {
            try store.save(event, span: .thisEvent)
            print("[Calendar] Created event: \(event.eventIdentifier ?? "unknown")")
            return event.eventIdentifier
        } catch {
            print("[Calendar] Failed to create event: \(error.localizedDescription)")
            return nil
        }
    }

    /// Remove a calendar event by its identifier.
    static func removeEvent(identifier: String) {
        guard hasAccess else { return }
        guard let event = store.event(withIdentifier: identifier) else { return }

        do {
            try store.remove(event, span: .futureEvents)
            print("[Calendar] Removed event: \(identifier)")
        } catch {
            print("[Calendar] Failed to remove event: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func parseTimeHint(_ hint: String?) -> (Int, Int) {
        guard let hint = hint, !hint.isEmpty else {
            return (9, 0)
        }

        let parts = hint.split(separator: ":")
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
            return (h, m)
        }

        switch hint.lowercased() {
        case "morning": return (7, 30)
        case "afternoon": return (14, 0)
        case "evening": return (19, 0)
        case "night": return (21, 0)
        default: return (9, 0)
        }
    }
}
