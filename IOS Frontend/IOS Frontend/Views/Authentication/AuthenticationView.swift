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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 44)
                        brand(timeOfDay: timeOfDay)

                        VStack(spacing: 14) {
                            usernameField(timeOfDay: timeOfDay)
                            passwordField(timeOfDay: timeOfDay)

                            if let error = authentication.errorMessage {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(Color.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                            }

                            signInButton(timeOfDay: timeOfDay)
                        }
                        .padding(.top, 42)

                        HStack(spacing: 5) {
                            Text("New to Repbase?")
                                .foregroundStyle(timeOfDay.secondaryText)
                            Button("Create an account") {
                                authentication.clearError()
                                isCreatingAccount = true
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(timeOfDay.accent)
                            .disabled(authentication.isWorking)
                        }
                        .font(.subheadline)
                        .padding(.top, 24)

                        Spacer(minLength: 34)

#if DEBUG
                        Label(
                            "Development · \(authentication.configuration.displayName)",
                            systemImage: "hammer"
                        )
                        .font(.caption2)
                        .foregroundStyle(timeOfDay.secondaryText.opacity(0.72))
#endif
                    }
                    .padding(.horizontal, 26)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .homeTimeScreen(timeOfDay)
        }
        .fullScreenCover(isPresented: $isCreatingAccount) {
            NavigationStack {
                AccountRegistrationView()
            }
        }
    }

    private func brand(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(RepbasePalette.cream)
                .frame(width: 54, height: 54)
                .background(RepbasePalette.charcoal, in: RoundedRectangle(cornerRadius: 17))
                .shadow(color: timeOfDay.shadow.opacity(0.72), radius: 9, x: 0, y: 6)

            VStack(spacing: 4) {
                Text("Repbase")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Welcome back")
                    .font(.subheadline)
                    .foregroundStyle(timeOfDay.secondaryText)
            }
        }
    }

    private func usernameField(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person")
                .foregroundStyle(timeOfDay.secondaryText)
                .frame(width: 20)
            TextField("Username", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .authenticationField(timeOfDay: timeOfDay)
    }

    private func passwordField(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .foregroundStyle(timeOfDay.secondaryText)
                .frame(width: 20)
            SecureField("Password", text: $password)
                .textContentType(.password)
        }
        .authenticationField(timeOfDay: timeOfDay)
    }

    private func signInButton(timeOfDay: HomeTimeOfDay) -> some View {
        Button { submit() } label: {
            HStack(spacing: 9) {
                if authentication.isWorking {
                    ProgressView().tint(Color.white)
                }
                Text("Sign In")
                Image(systemName: "arrow.right")
            }
            .font(.headline.weight(.bold))
            .foregroundStyle(RepbasePalette.cream)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(RepbasePalette.charcoal, in: RoundedRectangle(cornerRadius: 17))
            .shadow(color: timeOfDay.shadow.opacity(0.72), radius: 9, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || authentication.isWorking)
        .opacity(canSubmit ? 1 : 0.42)
        .padding(.top, 4)
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
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Text("Create Account").font(.headline.weight(.bold))
                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("JOIN REPBASE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.3)
                            .foregroundStyle(timeOfDay.accent)
                        Text("Create your account.")
                            .font(.system(size: 34, weight: .bold))
                        Text("Goals, measurements, your photo, disciplines, and gym can be added later from Profile Settings.")
                            .font(.subheadline)
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
                            .font(.caption)
                            .foregroundStyle(timeOfDay.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = authentication.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button { register() } label: {
                        HStack {
                            if authentication.isWorking { ProgressView().tint(.white) }
                            Text("Create Account")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline.weight(.bold))
                        .foregroundStyle(RepbasePalette.cream)
                        .padding(.horizontal, 20)
                        .frame(height: 56)
                        .background(RepbasePalette.charcoal, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canRegister || authentication.isWorking)
                    .opacity(canRegister ? 1 : 0.42)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
        }
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
            .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(timeOfDay.border, lineWidth: 1)
            }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
