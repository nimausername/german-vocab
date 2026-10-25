import Foundation
import UserNotifications

/// How often reminders fire, stored on this device.
struct ReminderPreferences: Equatable, Codable {
    var enabled: Bool
    var timesPerDay: Int
    var startMinutes: Int
    var endMinutes: Int

    static let `default` = ReminderPreferences(
        enabled: true,
        timesPerDay: 2,
        startMinutes: 9 * 60,
        endMinutes: 20 * 60
    )

    private static let storageKey = "reminderPreferences"

    static func load() -> ReminderPreferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(ReminderPreferences.self, from: data) else {
            return .default
        }
        return stored.clamped()
    }

    func save() {
        let value = clamped()
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func clamped() -> ReminderPreferences {
        var copy = self
        copy.timesPerDay = min(4, max(1, timesPerDay))
        copy.startMinutes = min(23 * 60, max(0, startMinutes))
        let latest = 23 * 60 + 45
        if copy.timesPerDay == 1 {
            copy.endMinutes = copy.startMinutes
        } else {
            copy.endMinutes = min(latest, max(copy.startMinutes + 30, endMinutes))
        }
        return copy
    }

    /// Evenly spaced minutes from midnight, from the first reminder to the last.
    func reminderMinutes() -> [Int] {
        let prefs = clamped()
        if prefs.timesPerDay <= 1 {
            return [prefs.startMinutes]
        }
        let span = prefs.endMinutes - prefs.startMinutes
        return (0..<prefs.timesPerDay).map { index in
            prefs.startMinutes + (span * index) / (prefs.timesPerDay - 1)
        }
    }
}

/// Latest study snapshot used to choose reminder copy.
struct ReminderContext: Equatable, Codable {
    var streak: Int
    var studiedToday: Bool
    var wordCount: Int

    private static let storageKey = "reminderContext"

    static func load() -> ReminderContext {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(ReminderContext.self, from: data) else {
            return ReminderContext(streak: 0, studiedToday: false, wordCount: 0)
        }
        return stored
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

/// Local reminders for iPhone and iPad. A locked iPhone mirrors them to Apple Watch.
enum StudyNotificationScheduler {
    private static let scheduledIDsKey = "scheduledReminderIDs"
    private static let legacyID = "daily-study"

    static func reschedule() async {
        let center = UNUserNotificationCenter.current()
        clearPending(center)

        let preferences = ReminderPreferences.load()
        guard preferences.enabled else { return }
        guard await authorizationGranted(center) else { return }

        let context = ReminderContext.load()
        let calendar = Calendar.current
        let now = Date()
        var identifiers: [String] = []

        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) else {
                continue
            }
            let isToday = dayOffset == 0
            if isToday && context.studiedToday {
                continue
            }

            for (index, minutes) in preferences.reminderMinutes().enumerated() {
                guard let fireDate = date(on: day, minutes: minutes, calendar: calendar),
                      fireDate > now.addingTimeInterval(30) else {
                    continue
                }

                let content = UNMutableNotificationContent()
                content.title = "German Vocab"
                content.sound = .default
                content.body = message(
                    minutes: minutes,
                    context: context,
                    includeCount: isToday,
                    day: day,
                    index: index,
                    calendar: calendar
                )

                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                let identifier = "study-reminder-\(dayOffset)-\(index)"
                identifiers.append(identifier)
                try? await center.add(
                    UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                )
            }
        }

        UserDefaults.standard.set(identifiers, forKey: scheduledIDsKey)
    }

    private static func clearPending(_ center: UNUserNotificationCenter) {
        let previous = UserDefaults.standard.stringArray(forKey: scheduledIDsKey) ?? []
        center.removePendingNotificationRequests(withIdentifiers: previous + [legacyID])
        UserDefaults.standard.removeObject(forKey: scheduledIDsKey)
    }

    private static func authorizationGranted(_ center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func date(on day: Date, minutes: Int, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        return calendar.date(from: parts)
    }

    private static func message(
        minutes: Int,
        context: ReminderContext,
        includeCount: Bool,
        day: Date,
        index: Int,
        calendar: Calendar
    ) -> String {
        let hour = minutes / 60
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: day) ?? 1
        if context.streak > 0 && hour >= 17 {
            let lines = streakLines(context.streak)
            return lines[(dayOfYear + index) % lines.count]
        }

        if includeCount && context.wordCount > 0 {
            let countLine = context.wordCount == 1
                ? "1 word is ready."
                : "\(context.wordCount) words are ready."
            let lines = [countLine] + practiceLines
            return lines[(dayOfYear + index) % lines.count]
        }

        return practiceLines[(dayOfYear + index) % practiceLines.count]
    }

    private static let practiceLines = [
        "Your German words are set out.",
        "A short session is enough for today.",
        "Five quiet minutes. That's the exercise.",
        "Today's words are ready when you are.",
        "The vocabulary can wait, but it would rather not.",
    ]

    private static func streakLines(_ streak: Int) -> [String] {
        let days = streak == 1 ? "1-day" : "\(streak)-day"
        return [
            "Your \(days) streak clocks out at midnight.",
            "One review keeps a \(days) streak from starting over.",
            "Midnight resets \(streak) \(streak == 1 ? "day" : "days"). A single word does not.",
            "Your streak has shown up for \(streak) \(streak == 1 ? "day" : "days"). Your turn.",
            "The \(days) streak is fine. It is also watching the clock.",
        ]
    }
}

final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
