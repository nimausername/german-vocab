import SwiftUI

@main
struct WatchApp: App {
    @StateObject private var study = WatchStudyModel()

    init() {
        NotificationPresenter.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchStudyView(model: study)
                .tint(AppTheme.accent)
                .task {
                    await StudyNotificationScheduler.reschedule()
                }
        }
    }
}
