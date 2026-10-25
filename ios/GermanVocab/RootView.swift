import SwiftUI

private enum AppSection: Hashable {
    case today
    case words
    case stats
    case settings
}

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if session.isAuthenticated {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(AppMotion.reveal, value: session.isAuthenticated)
        .sensoryFeedback(.success, trigger: session.isAuthenticated) { _, signedIn in
            signedIn
        }
    }
}

struct MainTabView: View {
    @State private var section: AppSection = .today

    var body: some View {
        TabView(selection: $section) {
            if #available(iOS 27, *) {
                Tab("Today", systemImage: "sun.max", value: AppSection.today, role: .prominent) {
                    TodayView()
                }
            } else {
                Tab("Today", systemImage: "sun.max", value: AppSection.today) {
                    TodayView()
                }
            }

            Tab("Words", systemImage: "text.book.closed", value: AppSection.words) {
                WordsView()
            }

            Tab("Stats", systemImage: "chart.bar", value: AppSection.stats) {
                StatsView()
            }

            Tab("Settings", systemImage: "gearshape", value: AppSection.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sensoryFeedback(.selection, trigger: section)
    }
}
