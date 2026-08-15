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
    @State private var mode: Mode = .login
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(WorkoutVisualPhase.prepare.accent)
                            .frame(width: 82, height: 82)
                            .background(
                                WorkoutVisualPhase.prepare.accent.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 24)
                            )
                        Text("Repbase")
                            .font(.largeTitle.weight(.bold))
                        Text("Sign in to sync workouts and sessions with your account.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Picker("Authentication mode", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) {
                        authentication.clearError()
                    }

                    VStack(spacing: 12) {
                        if mode == .register {
                            HStack(spacing: 10) {
                                TextField("First name", text: $firstName)
                                    .textContentType(.givenName)
                                    .authenticationField()
                                TextField("Last name", text: $lastName)
                                    .textContentType(.familyName)
                                    .authenticationField()
                            }

                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .authenticationField()
                        }

                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .authenticationField()

                        SecureField("Password", text: $password)
                            .textContentType(mode == .login ? .password : .newPassword)
                            .authenticationField()

                        if mode == .register {
                            Text("Use at least 8 characters.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let error = authentication.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        submit()
                    } label: {
                        HStack {
                            if authentication.isWorking {
                                ProgressView()
                                    .tint(Color.white)
                            }
                            Text(mode.rawValue)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WorkoutPrimaryButtonStyle(phase: .prepare))
                    .disabled(!canSubmit || authentication.isWorking)

#if DEBUG
                    Label(
                        "Development server: \(authentication.configuration.displayName)",
                        systemImage: "hammer.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
#endif
                }
                .padding()
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .repbaseScreen(.prepare)
        }
    }

    private var canSubmit: Bool {
        let hasCredentials = !username.trimmed.isEmpty && !password.isEmpty
        guard mode == .register else { return hasCredentials }
        return hasCredentials
            && password.count >= 8
            && !email.trimmed.isEmpty
            && !firstName.trimmed.isEmpty
            && !lastName.trimmed.isEmpty
    }

    private func submit() {
        Task {
            if mode == .login {
                await authentication.login(
                    username: username.trimmed,
                    password: password
                )
            } else {
                await authentication.register(
                    username: username.trimmed,
                    email: email.trimmed,
                    password: password,
                    firstName: firstName.trimmed,
                    lastName: lastName.trimmed
                )
            }
        }
    }
}

private extension View {
    func authenticationField() -> some View {
        padding(13)
            .repbaseControlSurface(cornerRadius: 12)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
