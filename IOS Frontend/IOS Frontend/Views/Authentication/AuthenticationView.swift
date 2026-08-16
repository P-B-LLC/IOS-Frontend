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

                    // Signing in is a form; creating an account is a walk
                    // through several pages. Putting both behind one segmented
                    // control meant the whole of account creation had to fit on
                    // this screen at once.
                    VStack(spacing: 12) {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .authenticationField()

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .authenticationField()
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
                            Text("Sign In")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WorkoutPrimaryButtonStyle(phase: .prepare))
                    .disabled(!canSubmit || authentication.isWorking)

                    Button {
                        authentication.clearError()
                        isCreatingAccount = true
                    } label: {
                        Text("Create Account")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(authentication.isWorking)

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
        .fullScreenCover(isPresented: $isCreatingAccount) {
            NavigationStack {
                ProfileOnboardingView(seed: .empty)
            }
        }
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
