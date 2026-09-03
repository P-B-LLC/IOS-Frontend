//
//  AuthenticationView.swift
//  IOS Frontend
//
//  Login and account creation for the protected Repbase API.
//

import SwiftUI

struct AuthenticationView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case login = "Sign In"
        case register = "Create Account"

        var id: String { rawValue }
    }

    @Environment(AuthenticationStore.self) private var authentication
    @State private var username = ""
    @State private var password = ""
    @State private var isCreatingAccount = false
    @State private var hasEntered = false
    @State private var showsPasswordReset = false
    @State private var showsPassword = false

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        // Grouped so the screen modifier below has something to attach
        // to. A modifier cannot be applied to a bare if/else in a
        // ViewBuilder, and the compiler reports that as `homeTimeScreen`
        // being used on the type `View` rather than on a value.
        Group {
        if hasEntered {
            GeometryReader { geometry in
                ZStack(alignment: .topTrailing) {
                    loginFlowBackground(timeOfDay: timeOfDay)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer(minLength: 74)
                            brand(timeOfDay: timeOfDay)

                            Text("Welcome back to your rhythm.")
                                .font(.community(size: 31, weight: .bold))
                                .tracking(-0.62)
                                .foregroundStyle(timeOfDay.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 42)

                            Text("Pick up where you left off.")
                                .font(.community(.subheadline))
                                .foregroundStyle(timeOfDay.secondaryText)
                                .padding(.top, 8)

                            VStack(spacing: 22) {
                                usernameField(timeOfDay: timeOfDay)
                                passwordField(timeOfDay: timeOfDay)
                            }
                            .padding(.top, 40)

                            Button("Forgot password?") {
                                authentication.clearError()
                                showsPasswordReset = true
                            }
                            .font(.community(.caption, weight: .semibold))
                            .foregroundStyle(timeOfDay.accent)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .disabled(authentication.isWorking)
                            .padding(.top, 20)

                            if let error = authentication.errorMessage {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.community(.footnote))
                                    .foregroundStyle(Color.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 16)
                            }

                            signInButton(timeOfDay: timeOfDay)
                                .padding(.top, 14)

                            HStack(spacing: 5) {
                                Text("New to Rytivo?")
                                    .foregroundStyle(timeOfDay.secondaryText)
                                Button("Create an account") {
                                    authentication.clearError()
                                    isCreatingAccount = true
                                }
                                .font(.community(.subheadline, weight: .semibold))
                                .foregroundStyle(timeOfDay.accent)
                                .disabled(authentication.isWorking)
                            }
                            .font(.community(.subheadline))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 38)

                            Text("Move well. Eat well. Become more.")
                                .font(.community(.caption2))
                                .tracking(0.44)
                                .foregroundStyle(timeOfDay.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 10)

                            Spacer(minLength: 34)

#if DEBUG
                            Label(
                                "Development · \(authentication.configuration.displayName)",
                                systemImage: "hammer"
                            )
                            .font(.community(.caption2))
                            .foregroundStyle(timeOfDay.secondaryText.opacity(0.62))
                            .frame(maxWidth: .infinity)
#endif
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                        .frame(maxWidth: 480)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        } else {
            welcome(timeOfDay: timeOfDay)
        }
        }
        .homeTimeScreen(timeOfDay)
        .fullScreenCover(isPresented: $isCreatingAccount) {
            NavigationStack {
                AccountRegistrationView()
            }
        }
        .fullScreenCover(isPresented: $showsPasswordReset) {
            NavigationStack {
                PasswordResetView()
            }
        }
#if DEBUG
        .task {
            // Same launch flag, so the cover is already open on arrival.
            if ProcessInfo.processInfo.environment["REPBASE_RESET_PREVIEW"] != nil {
                hasEntered = true
                showsPasswordReset = true
            }
        }
#endif
    }

    private func welcome(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 70)

            HStack(spacing: 10) {
                Image("RytivoLogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                    .accessibilityHidden(true)

                Text("Rytivo")
                    .font(.community(size: 24, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(timeOfDay.primaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rytivo")

            Text("Plan. Execute. Inspire.")
                .font(.community(size: 11, weight: .bold))
                .tracking(1.15)
                .foregroundStyle(timeOfDay.accent)
                .padding(.top, 8)
                .accessibilityLabel("Plan. Execute. Inspire.")

            Text("Everything important,\nin one flow.")
                .font(.community(size: 42, weight: .bold))
                .tracking(-1.2)
                .padding(.top, 14)

            Text("Plan training, understand nutrition, and share progress without fighting the interface.")
                .font(.community(.body))
                .foregroundStyle(timeOfDay.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { hasEntered = true }
                } label: {
                    HStack {
                        Text("Sign In")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(RepbasePrimaryButtonStyle())

                Button {
                    authentication.clearError()
                    isCreatingAccount = true
                } label: {
                    Text("Create an account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RepbaseQuietButtonStyle())
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
    }

    private func brand(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 14) {
            Image("RytivoLogoMark")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR DAY, IN MOTION")
                    .font(.community(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(timeOfDay.accent)
                Text("Rytivo")
                    .font(.community(size: 29, weight: .bold))
                    .tracking(-0.58)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rytivo. Your day, in motion.")
    }

    private func usernameField(timeOfDay: HomeTimeOfDay) -> some View {
        authenticationLineField(
            title: "USERNAME",
            systemImage: "person",
            timeOfDay: timeOfDay
        ) {
            TextField("Enter your username", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private func passwordField(timeOfDay: HomeTimeOfDay) -> some View {
        authenticationLineField(
            title: "PASSWORD",
            systemImage: "lock",
            timeOfDay: timeOfDay
        ) {
            Group {
                if showsPassword {
                    TextField("Enter your password", text: $password)
                } else {
                    SecureField("Enter your password", text: $password)
                }
            }
            .textContentType(.password)

            Button {
                showsPassword.toggle()
            } label: {
                Image(systemName: showsPassword ? "eye.slash" : "eye")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(timeOfDay.secondaryText)
            .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
        }
    }

    private func signInButton(timeOfDay: HomeTimeOfDay) -> some View {
        Button { submit() } label: {
            HStack(spacing: 12) {
                if authentication.isWorking {
                    ProgressView().tint(timeOfDay.onPrimaryAction)
                }
                Text("Sign in")
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.community(.subheadline, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 32, height: 32)
                    .background(timeOfDay.accent, in: Circle())
            }
            .font(.community(.body, weight: .semibold))
            .foregroundStyle(timeOfDay.onPrimaryAction)
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                timeOfDay.primaryActionSurface,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .shadow(color: timeOfDay.shadow.opacity(0.55), radius: 13, y: 7)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || authentication.isWorking)
        .opacity(canSubmit ? 1 : 0.42)
    }

    private func authenticationLineField<Content: View>(
        title: String,
        systemImage: String,
        timeOfDay: HomeTimeOfDay,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.community(.caption2, weight: .semibold))
                .tracking(0.88)
                .foregroundStyle(timeOfDay.secondaryText)
                .padding(.leading, 32)

            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.community(.body))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .frame(width: 20)
                content()
                    .font(.community(.body))
                    .foregroundStyle(timeOfDay.primaryText)
            }
            .frame(minHeight: 32)

            Rectangle()
                .fill(timeOfDay.border)
                .frame(height: 1)
        }
    }

    private func loginFlowBackground(timeOfDay: HomeTimeOfDay) -> some View {
        ZStack {
            Circle()
                .fill(timeOfDay.accent.opacity(0.075))
                .frame(width: 340, height: 340)
                .offset(x: 205, y: 18)
            Circle()
                .fill(timeOfDay.surfaceRaised.opacity(0.34))
                .frame(width: 240, height: 240)
                .offset(x: 76, y: 182)
        }
        .frame(width: 393, height: 470)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var canSubmit: Bool {
        !username.trimmed.isEmpty && !password.isEmpty
    }

    private func submit() {
        Task {
            await authentication.login(
                username: username.trimmed,
                password: password
            )
        }
    }
}

/// Creates only the backend account. Optional goals and public identity are
/// deliberately configured later from Profile → Settings.
private struct AccountRegistrationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationStore.self) private var authentication

    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.community(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Create Account").font(.community(.headline, weight: .bold))
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("JOIN RYTIVO")
                        .font(.community(size: 10, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(timeOfDay.accent)
                    Text("Create your account.")
                        .font(.community(size: 30, weight: .bold))
                        .tracking(-0.65)
                    Text("Goals, measurements, your photo, disciplines, and gym can be added later from Profile Settings.")
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 14) {
                    registrationField("First name", text: $firstName, contentType: .givenName, timeOfDay: timeOfDay)
                    registrationField("Last name", text: $lastName, contentType: .familyName, timeOfDay: timeOfDay)
                    registrationField("Username", text: $username, contentType: .username, timeOfDay: timeOfDay, lowercase: true)
                    registrationField("Email", text: $email, contentType: .emailAddress, timeOfDay: timeOfDay, lowercase: true)

                    HStack(spacing: 12) {
                        Image(systemName: "lock").foregroundStyle(timeOfDay.secondaryText)
                        SecureField("Password", text: $password)
                            .textContentType(.newPassword)
                    }
                    .authenticationField(timeOfDay: timeOfDay)

                    Text("Use at least 8 characters.")
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = authentication.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.community(.footnote))
                        .foregroundStyle(.red)
                }

                Button { register() } label: {
                    HStack {
                        if authentication.isWorking { ProgressView().tint(.white) }
                        Text("Create Account")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.community(.headline, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 56)
                    .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canRegister || authentication.isWorking)
                .opacity(canRegister ? 1 : 0.42)
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .homeTimeScreen(timeOfDay)
    }

    private func registrationField(
        _ title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        timeOfDay: HomeTimeOfDay,
        lowercase: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: title == "Email" ? "envelope" : "person")
                .foregroundStyle(timeOfDay.secondaryText)
                .frame(width: 20)
            TextField(title, text: text)
                .textContentType(contentType)
                .textInputAutocapitalization(lowercase ? .never : .words)
                .autocorrectionDisabled(lowercase)
                .keyboardType(title == "Email" ? .emailAddress : .default)
        }
        .authenticationField(timeOfDay: timeOfDay)
    }

    private var canRegister: Bool {
        !firstName.trimmed.isEmpty
            && !lastName.trimmed.isEmpty
            && !username.trimmed.isEmpty
            && email.contains("@")
            && password.count >= 8
    }

    private func register() {
        Task {
            await authentication.register(
                username: username.trimmed,
                email: email.trimmed,
                password: password,
                firstName: firstName.trimmed,
                lastName: lastName.trimmed
            )
            if authentication.token != nil { dismiss() }
        }
    }
}

private extension View {
    func authenticationField(timeOfDay: HomeTimeOfDay) -> some View {
        padding(.horizontal, 15)
            .frame(height: 55)
            .repbaseInsetSurface(cornerRadius: 14)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
