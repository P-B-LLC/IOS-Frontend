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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            // Grouped so the screen modifier below has something to attach
            // to. A modifier cannot be applied to a bare if/else in a
            // ViewBuilder, and the compiler reports that as `homeTimeScreen`
            // being used on the type `View` rather than on a value.
            Group {
            if hasEntered {
                GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 56)
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
                        .padding(.top, 38)

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
                    .padding(.horizontal, RepbaseDesign.pageInset)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
                }
            } else {
                welcome(timeOfDay: timeOfDay)
            }
            }
            .homeTimeScreen(timeOfDay)
        }
        .fullScreenCover(isPresented: $isCreatingAccount) {
            NavigationStack {
                AccountRegistrationView()
            }
        }
    }

    private func welcome(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 70)

            Text("REPBASE")
                .font(.caption.weight(.bold))
                .tracking(2.2)
                .foregroundStyle(timeOfDay.accent)

            Text("Everything important,\nin one flow.")
                .font(.system(size: 42, weight: .bold))
                .tracking(-1.2)
                .padding(.top, 14)

            Text("Plan training, understand nutrition, and share progress without fighting the interface.")
                .font(.body)
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
            ActivityIconArtwork(kind: .lifting, size: 27, color: Color.white)
                .frame(width: 50, height: 50)
                .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("TRAINING, ORGANIZED")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.35)
                    .foregroundStyle(timeOfDay.accent)
                Text("Repbase")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.65)
                Text("Welcome back")
                    .font(.subheadline)
                    .foregroundStyle(timeOfDay.secondaryText)
            }
            Spacer(minLength: 0)
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
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 12))
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
                            .font(.system(size: 30, weight: .bold))
                            .tracking(-0.65)
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
