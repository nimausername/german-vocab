import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case username, password
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .accessibilityLabel("Username")

                    SecureField("Password", text: $password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await signIn() } }
                        .accessibilityLabel("Password")
                } header: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("German Vocab")
                            .font(AppTheme.display(34, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .textCase(nil)
                        Text("Daily German, scheduled with care.")
                            .font(AppTheme.body())
                            .foregroundStyle(AppTheme.muted)
                            .textCase(nil)
                    }
                    .padding(.bottom, 12)
                    .accessibilityElement(children: .combine)
                } footer: {
                    if let errorMessage = session.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.danger)
                    }
                }

                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        if session.isBusy {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Sign in")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSubmit || session.isBusy)
                    .accessibilityLabel("Sign in")
                }
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.interactively)
            .tint(AppTheme.accent)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private func signIn() async {
        guard canSubmit else { return }
        await session.login(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
    }
}
