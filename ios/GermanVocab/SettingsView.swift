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
                    Text("On a physical iPhone or iPad, point AppConfig.apiBaseURL at your Mac’s LAN IP when the API is not public.")
                }

                Section {
                    LabeledContent("Daily reminder", value: "9:00")
                } footer: {
                    Text("The iPhone or iPad sends one reminder each morning. Apple Watch shows that same reminder when the iPhone is locked.")
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
