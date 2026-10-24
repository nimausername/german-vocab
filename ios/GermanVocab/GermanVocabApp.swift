import SwiftUI

@main
struct GermanVocabApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .tint(AppTheme.accent)
        }
    }
}
