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
    /// Cards still in today's queue (same as goal remaining when the plan is fresh).
    var wordCount: Int
    /// Cards left for today's goal. Falls back to `wordCount` on older payloads.
    var goalRemaining: Int

    private static let storageKey = "reminderContext"

    static func load() -> ReminderContext {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(ReminderContext.self, from: data) else {
            return ReminderContext(streak: 0, studiedToday: false, wordCount: 0, goalRemaining: 0)
        }
        return stored
    }

    enum CodingKeys: String, CodingKey {
        case streak, studiedToday, wordCount, goalRemaining
    }

    init(streak: Int, studiedToday: Bool, wordCount: Int, goalRemaining: Int? = nil) {
        self.streak = streak
        self.studiedToday = studiedToday
        self.wordCount = wordCount
        self.goalRemaining = goalRemaining ?? wordCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streak = try container.decode(Int.self, forKey: .streak)
        studiedToday = try container.decode(Bool.self, forKey: .studiedToday)
        wordCount = try container.decode(Int.self, forKey: .wordCount)
        goalRemaining = try container.decodeIfPresent(Int.self, forKey: .goalRemaining) ?? wordCount
    }

    /// Builds a reminder snapshot from today's plan.
    static func from(plan: TodayPlan) -> ReminderContext {
        ReminderContext(
            streak: plan.streak,
            studiedToday: plan.studiedToday || plan.dailyGoal.met,
            wordCount: plan.queue.count,
            goalRemaining: plan.dailyGoal.remaining
        )
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

/// Repeating local reminders. Each device schedules its own, so the watch alerts even when the iPhone is locked.
@MainActor
enum StudyNotificationScheduler {
    private static let legacyID = "daily-study"
    static var lastFailure: String?

    /// Writes a schedule received from the other device, then queues its notifications.
    static func applySyncedPayload(_ payload: [String: Any]) async {
        guard payload[WatchSyncKey.reminderMinutes] != nil else { return }
        let minutes = (payload[WatchSyncKey.reminderMinutes] as? String ?? "")
            .split(separator: ",")
            .compactMap { Int($0) }
        guard !minutes.isEmpty else { return }

        var preferences = ReminderPreferences.load()
        preferences.enabled = (payload[WatchSyncKey.remindersEnabled] as? String) != "0"
        preferences.timesPerDay = minutes.count
        preferences.startMinutes = minutes[0]
        preferences.endMinutes = minutes[minutes.count - 1]
        preferences.save()

        if payload[WatchSyncKey.reminderStreak] != nil {
            let words = Int(payload[WatchSyncKey.reminderWords] as? String ?? "") ?? 0
            let goal = Int(payload[WatchSyncKey.reminderGoal] as? String ?? "") ?? words
            ReminderContext(
                streak: Int(payload[WatchSyncKey.reminderStreak] as? String ?? "") ?? 0,
                studiedToday: (payload[WatchSyncKey.reminderStudied] as? String) == "1",
                wordCount: words,
                goalRemaining: goal
            ).save()
        }
        await reschedule()
    }

    static func reschedule() async {
        let center = UNUserNotificationCenter.current()
        await clearPending(center)
        lastFailure = nil

        let preferences = ReminderPreferences.load()
        guard preferences.enabled else { return }
        guard await authorizationGranted(center) else {
            lastFailure = "Notifications are off for German Vocab. Allow them in Settings → Notifications."
            return
        }

        let context = ReminderContext.load()
        let minutes = preferences.reminderMinutes()
        for (index, minute) in minutes.enumerated() {
            var parts = DateComponents()
            parts.hour = minute / 60
            parts.minute = minute % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
            let request = UNNotificationRequest(
                identifier: "study-reminder-daily-\(index)",
                content: content(
                    body: message(minutes: minute, context: context, index: index, total: minutes.count)
                ),
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                lastFailure = error.localizedDescription
            }
        }
    }

    /// Fires one reminder soon so the device can prove notifications are allowed.
    static func sendTest() async -> String {
        let center = UNUserNotificationCenter.current()
        guard await authorizationGranted(center) else {
            return "Notifications are off for German Vocab. Allow them in Settings → Notifications."
        }
        let context = ReminderContext.load()
        let body = message(minutes: 17 * 60, context: context, index: 0, total: 1)
        let request = UNNotificationRequest(
            identifier: "study-reminder-test",
            content: content(body: "Reminders are on. \(body)"),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        do {
            try await center.add(request)
        } catch {
            lastFailure = error.localizedDescription
            return error.localizedDescription
        }
        return "A test reminder arrives in a few seconds on this device and on Apple Watch when the phone is locked."
    }

    static func nextFireDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let preferences = ReminderPreferences.load()
        guard preferences.enabled else { return nil }
        return preferences.reminderMinutes().compactMap { minutes in
            var parts = calendar.dateComponents([.year, .month, .day], from: now)
            parts.hour = minutes / 60
            parts.minute = minutes % 60
            guard let today = calendar.date(from: parts) else { return nil }
            return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
        }.min()
    }

    private static func content(body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "German Vocab"
        content.body = body
        content.sound = .default
        content.threadIdentifier = "german-vocab-study"
        // Helps the watch surface the alert when the iPhone is locked.
        content.interruptionLevel = .timeSensitive
        return content
    }

    private static func clearPending(_ center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { identifier in
            identifier != "study-reminder-test"
                && (identifier.hasPrefix("study-reminder") || identifier == legacyID)
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
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

    private static func message(
        minutes: Int,
        context: ReminderContext,
        index: Int,
        total: Int
    ) -> String {
        let hour = minutes / 60
        let remaining = max(context.goalRemaining, context.wordCount)
        let isLaterSlot = total <= 1 ? hour >= 17 : index >= max(0, total - 1) || hour >= 17

        if context.studiedToday || remaining == 0 {
            if hour >= 17 {
                return "Today is done. Your streak is safe until tomorrow."
            }
            return "Today’s goal is finished. Come back tomorrow."
        }

        if isLaterSlot, context.streak > 0 {
            let lines = streakLines(streak: context.streak, remaining: remaining)
            return lines[index % lines.count]
        }

        if remaining > 0 {
            let countLine = remaining == 1
                ? "1 card left for today’s goal."
                : "\(remaining) cards left for today’s goal."
            let lines = [countLine] + practiceLines
            return lines[index % lines.count]
        }

        return practiceLines[index % practiceLines.count]
    }

    private static let practiceLines = [
        "Your German words are set out.",
        "A short session is enough for today.",
        "Five quiet minutes. That's the exercise.",
        "Today's words are ready when you are.",
        "The vocabulary can wait, but it would rather not.",
    ]

    private static func streakLines(streak: Int, remaining: Int) -> [String] {
        let days = streak == 1 ? "1-day" : "\(streak)-day"
        let cards = remaining == 1 ? "1 card" : "\(remaining) cards"
        return [
            "Your \(days) streak clocks out at midnight. \(cards) still open.",
            "One review keeps a \(days) streak from starting over.",
            "Midnight resets \(streak) \(streak == 1 ? "day" : "days"). \(cards) left today.",
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
