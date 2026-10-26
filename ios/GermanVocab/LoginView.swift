import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var mode: Mode = .signIn
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var didAppear = false
    @State private var showPassword = false
    @FocusState private var focusedField: Field?

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn
        case createAccount

        var id: String { rawValue }

        var actionTitle: String {
            switch self {
            case .signIn: return "Sign In"
            case .createAccount: return "Create Account"
            }
        }

        var switchPrompt: String {
            switch self {
            case .signIn: return "New here?"
            case .createAccount: return "Already learning?"
            }
        }

        var switchAction: String {
            switch self {
            case .signIn: return "Create an account"
            case .createAccount: return "Sign in"
            }
        }
    }

    private enum Field {
        case username, email, password
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                authAtmosphere
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        brandBlock
                            .padding(.top, max(24, geometry.safeAreaInsets.top * 0.2))
                            .padding(.bottom, 36)

                        formCard
                            .opacity(didAppear ? 1 : 0)
                            .offset(y: didAppear ? 0 : 18)
                            .animation(AppMotion.reveal.delay(0.08), value: didAppear)

                        Spacer(minLength: 28)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaBar(edge: .bottom) {
                    BottomActionBar(spacing: 12) {
                        if let errorMessage = session.errorMessage {
                            feedbackBanner(errorMessage)
                                .actionColumn()
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            Group {
                                if session.isBusy {
                                    ProgressView()
                                        .tint(AppTheme.ink)
                                } else {
                                    Text(mode.actionTitle)
                                        .font(.body.weight(.semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 24)
                        }
                        .prominentGlassCapsule()
                        .tint(AppTheme.accent)
                        .actionColumn()
                        .disabled(!canSubmit || session.isBusy)
                        .accessibilityLabel(session.isBusy ? "Working" : mode.actionTitle)
                        .sensoryFeedback(.impact(flexibility: .soft), trigger: session.isBusy)

                        switchModeRow
                            .actionColumn()
                    }
                }
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
        .animation(AppMotion.reveal, value: session.errorMessage)
        .animation(AppMotion.step, value: mode)
    }

    private var authAtmosphere: some View {
        ZStack {
            Color(AppTheme.ink)

            LinearGradient(
                colors: [
                    AppTheme.flagRed.opacity(0.42),
                    AppTheme.ink.opacity(0.15),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .center
            )

            LinearGradient(
                colors: [
                    Color.clear,
                    AppTheme.accent.opacity(0.28),
                    AppTheme.accent.opacity(0.08),
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )

            // Soft paper wash behind the form so fields stay readable.
            VStack {
                Spacer()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.systemBackground).opacity(0),
                                Color(.systemBackground).opacity(0.88),
                                Color(.systemBackground),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 420)
            }
        }
    }

    private var brandBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            BrandMark(size: 72)
                .scaleEffect(didAppear ? 1 : 0.9)
                .opacity(didAppear ? 1 : 0)
                .animation(AppMotion.reveal, value: didAppear)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)

            Text("German Vocab")
                .font(.system(size: 40, weight: .medium, design: .serif))
                .foregroundStyle(.white)
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 8)
                .animation(AppMotion.reveal.delay(0.04), value: didAppear)
                .accessibilityAddTraits(.isHeader)

            Text(mode == .signIn
                 ? "Pick up today’s words."
                 : "Start a spaced German practice.")
                .font(.title3.weight(.regular))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            fieldBlock(
                title: "Username",
                hint: mode == .createAccount ? "Letters, numbers, . _ -" : nil
            ) {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = mode == .createAccount ? .email : .password
                    }
            }

            if mode == .createAccount {
                fieldBlock(title: "Email", hint: "Optional") {
                    TextField("name@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            fieldBlock(
                title: "Password",
                hint: mode == .createAccount ? "At least 8 characters" : nil
            ) {
                HStack(spacing: 10) {
                    Group {
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textContentType(mode == .createAccount ? .newPassword : .password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func fieldBlock<Content: View>(
        title: String,
        hint: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let hint {
                    Spacer(minLength: 8)
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func feedbackBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.flagRed)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.flagRed.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Error. \(message)")
    }

    private var switchModeRow: some View {
        HStack(spacing: 6) {
            Text(mode.switchPrompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(mode.switchAction) {
                mode = mode == .signIn ? .createAccount : .signIn
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
            .accessibilityLabel(mode.switchAction)
        }
        .frame(maxWidth: .infinity)
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
            // If register recovered via sign-in after USERNAME_TAKEN, we're done.
            // If ACCOUNT_CREATED message was shown without tokens, switch mode.
            if !session.isAuthenticated,
               let message = session.errorMessage,
               message.localizedCaseInsensitiveContains("sign in") {
                mode = .signIn
            }
        }
    }
}
