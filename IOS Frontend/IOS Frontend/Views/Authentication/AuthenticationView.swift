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
                ProfileOnboardingView(seed: .empty)
            }
        }
    }

    private func brand(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 54, height: 54)
                .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 17))
                .shadow(color: timeOfDay.accent.opacity(0.22), radius: 9, x: 3, y: 6)

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
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 17))
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
