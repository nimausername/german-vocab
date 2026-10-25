import Foundation
import UserNotifications

/// Posts one local reminder each day. iPhone, iPad, and a locked iPhone’s paired Apple Watch all show it.
enum StudyNotificationScheduler {
    static let dailyIdentifier = "daily-study"
    static let hour = 9
    static let minute = 0

    static func scheduleDailyReminder(wordCount: Int) async {
        let center = UNUserNotificationCenter.current()
        let allowed = await authorizationGranted(center)
        guard allowed else { return }

        let content = UNMutableNotificationContent()
        content.title = "German Vocab"
        content.sound = .default
        content.body = wordCount == 1 ? "1 word is ready." : "\(wordCount) words are ready."

        var date = DateComponents()
        date.hour = hour
        date.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(
            identifier: dailyIdentifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
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
