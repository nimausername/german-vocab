import SwiftUI

@main
struct WatchApp: App {
    @StateObject private var study = WatchStudyModel()

    var body: some Scene {
        WindowGroup {
            WatchStudyView(model: study)
                .tint(AppTheme.accent)
        }
    }
}
