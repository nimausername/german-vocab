import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var mode: Mode = .signIn
    @State private var username = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
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
        case firstName, lastName, username, email, password
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(mode == .signIn
                         ? "Sign in to continue today’s plan on this iPhone or iPad."
                         : "Create an account to start today’s plan on this iPhone or iPad.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                }

                Section {
                    Picker("Account", selection: $mode) {
                        ForEach(Mode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("Account mode")
                }

                if mode == .createAccount {
                    Section {
                        TextField("First name", text: $firstName)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .firstName)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .lastName }

                        TextField("Last name", text: $lastName)
                            .textContentType(.familyName)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .lastName)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .username }
                    } header: {
                        Text("Your name")
                    } footer: {
                        Text("Used to welcome you in the app.")
                    }
                }

                Section {
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
                } header: {
                    Text("Account")
                } footer: {
                    Text(accountFooter)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("German Vocab")
            .navigationBarTitleDisplayMode(.large)
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaBar(edge: .bottom) {
                BottomActionBar(spacing: 12) {
                    if let errorMessage = session.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .accessibilityLabel("Error. \(errorMessage)")
                            .actionColumn()
                    }

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
                    .tint(AppTheme.accent)
                    .actionColumn()
                    .disabled(!canSubmit || session.isBusy)
                    .accessibilityLabel(session.isBusy ? "Working" : mode.title)
                }
            }
            .onAppear {
                focusedField = mode == .createAccount ? .firstName : .username
            }
            .onChange(of: mode) { _, newMode in
                session.errorMessage = nil
                focusedField = newMode == .createAccount ? .firstName : .username
            }
            .animation(AppMotion.reveal, value: session.errorMessage)
            .animation(AppMotion.step, value: mode)
        }
    }

    private var accountFooter: String {
        switch mode {
        case .signIn:
            return "Use the username and password for your German Vocab account."
        case .createAccount:
            return "Username needs at least 3 characters. Password needs at least 8. Email is optional."
        }
    }

    private var canSubmit: Bool {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else { return false }
        if mode == .createAccount {
            let given = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let family = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.count >= 3 && password.count >= 8 && !given.isEmpty && !family.isEmpty
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
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                email: trimmedEmail.isEmpty ? nil : trimmedEmail
            )
            if !session.isAuthenticated,
               let message = session.errorMessage,
               message.localizedCaseInsensitiveContains("sign in") {
                mode = .signIn
            }
        }
    }
}
