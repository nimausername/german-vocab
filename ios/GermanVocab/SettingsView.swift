import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("API base URL") {
                        Text(AppConfig.apiBaseURL.absoluteString)
                            .foregroundStyle(AppTheme.inkSoft)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("On a physical iPad, point AppConfig.apiBaseURL at your Mac’s LAN IP.")
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        session.logout()
                    }
                    .accessibilityLabel("Sign out")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .tint(AppTheme.accent)
        }
    }
}
