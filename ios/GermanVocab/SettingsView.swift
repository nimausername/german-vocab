import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("API base URL") {
                        Text(AppConfig.apiBaseURL.absoluteString)
                            .foregroundStyle(.secondary)
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
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
