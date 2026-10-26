import SwiftUI

@main
struct GermanVocabApp: App {
    @StateObject private var session = SessionStore()

    init() {
        NotificationPresenter.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .tint(AppTheme.accent)
                .background(Color(.systemBackground).ignoresSafeArea())
        }
    }
}
