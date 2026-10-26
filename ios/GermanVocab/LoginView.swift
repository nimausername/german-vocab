import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var mode: Mode = .signIn
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var didAppear = false
    @FocusState private var focusedField: Field?

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn
        case createAccount

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn: return "Sign In"
            case .createAccount: return "Create Account"
            }
        }
    }

    private enum Field {
        case username, email, password
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

                        Text(mode == .signIn
                            ? "Sign in to pick up today’s words on this iPhone or iPad."
                            : "Create an account to start today’s words on this iPhone or iPad.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
                .listRowBackground(Color.clear)

                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Account mode")
                    .listRowBackground(Color.clear)
                }

                Section("Account") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = mode == .createAccount ? .email : .password
                        }

                    if mode == .createAccount {
                        TextField("Email (optional)", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                    }

                    SecureField("Password", text: $password)
                        .textContentType(mode == .createAccount ? .newPassword : .password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                }

                if mode == .createAccount {
                    Section {
                        Text("Use at least 8 characters. Username may include letters, numbers, dots, underscores, and hyphens.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
                        Task { await submit() }
                    } label: {
                        Group {
                            if session.isBusy {
                                ProgressView()
                            } else {
                                Text(mode.title)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .prominentGlassCapsule()
                    .actionColumn()
                    .disabled(!canSubmit || session.isBusy)
                    .accessibilityLabel(session.isBusy ? "Working" : mode.title)
                }
            }
            .onAppear {
                didAppear = true
                if username.isEmpty {
                    focusedField = .username
                }
            }
            .onChange(of: mode) { _, _ in
                session.errorMessage = nil
            }
        }
    }

    private var canSubmit: Bool {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else { return false }
        if mode == .createAccount {
            return name.count >= 3 && password.count >= 8
        }
        return true
    }

    private func submit() async {
        guard canSubmit else { return }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .signIn:
            await session.login(username: name, password: password)
        case .createAccount:
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            await session.register(
                username: name,
                password: password,
                email: trimmedEmail.isEmpty ? nil : trimmedEmail
            )
        }
    }
}
