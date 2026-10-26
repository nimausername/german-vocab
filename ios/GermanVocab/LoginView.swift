import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var username = ""
    @State private var password = ""
    @State private var didAppear = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case username, password
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        BrandMark(size: 64)
                            .scaleEffect(didAppear ? 1 : 0.92)
                            .opacity(didAppear ? 1 : 0)
                            .animation(AppMotion.reveal, value: didAppear)

                        Text("Daily German, scheduled with care.")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Sign in to pick up today’s words on this iPhone or iPad.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
                .listRowBackground(Color.clear)

                Section("Account") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await signIn() } }
                }

                if let errorMessage = session.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .accessibilityLabel("Error. \(errorMessage)")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("German Vocab")
            .navigationBarTitleDisplayMode(.large)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaBar(edge: .bottom) {
                BottomActionBar {
                    Button {
                        Task { await signIn() }
                    } label: {
                        Group {
                            if session.isBusy {
                                ProgressView()
                            } else {
                                Text("Sign In")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .prominentGlassCapsule()
                    .actionColumn()
                    .disabled(!canSubmit || session.isBusy)
                    .accessibilityLabel(session.isBusy ? "Signing in" : "Sign in")
                }
            }
            .onAppear {
                didAppear = true
                if username.isEmpty {
                    focusedField = .username
                }
            }
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
