//
//  PasswordResetView.swift
//  IOS Frontend
//
//  Getting back in after forgetting the password.
//

import SwiftUI

/// Two steps: ask for a code, then spend it on a new password.
///
/// The first step always advances, even for an address nobody has registered.
/// That is not an oversight — the server answers identically either way so
/// that this screen cannot be used to find out who has an account here, and a
/// screen that reported "no such address" would give away exactly what the
/// server declines to. The wording below is written to be honest about that
/// rather than to imply a code is definitely coming.
struct PasswordResetView: View {
    enum Step {
        case askingForCode
        case enteringCode
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationStore.self) private var authentication

    @State private var step: Step = .askingForCode
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case code
        case password
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    switch step {
                    case .askingForCode:
                        askForCode(timeOfDay: timeOfDay)
                    case .enteringCode:
                        enterCode(timeOfDay: timeOfDay)
                    }
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
#if DEBUG
            .task { applyPreviewFlag() }
#endif
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Reset Password").font(.headline.weight(.bold))
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: - Step one

    private func askForCode(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            title(
                eyebrow: "FORGOT YOUR PASSWORD",
                headline: "We can email you a code.",
                detail: "Enter the address on your account. The code is good "
                    + "for 15 minutes.",
                timeOfDay: timeOfDay
            )

            HStack(spacing: 12) {
                Image(systemName: "envelope")
                    .foregroundStyle(timeOfDay.secondaryText)
                    .frame(width: 20)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.send)
                    .onSubmit { sendCode() }
            }
            .resetField(timeOfDay: timeOfDay)

            problem

            primaryButton(
                "Send Code",
                icon: "paperplane.fill",
                enabled: email.contains("@"),
                timeOfDay: timeOfDay,
                action: sendCode
            )

            Button("I already have a code") {
                errorMessage = nil
                step = .enteringCode
                focusedField = .code
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(timeOfDay.accent)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Step two

    private func enterCode(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            title(
                eyebrow: "CHECK YOUR EMAIL",
                headline: "Enter the code.",
                // Deliberately conditional. The server does not say whether
                // the address is registered, so neither can this.
                detail: "If \(email.trimmedReset) has an account, a six digit "
                    + "code is on its way. It works once and expires in 15 "
                    + "minutes.",
                timeOfDay: timeOfDay
            )

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "number")
                        .foregroundStyle(timeOfDay.secondaryText)
                        .frame(width: 20)
                    TextField("6 digit code", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .code)
                        .onChange(of: code) { _, updated in
                            // Digits only, six of them. Autofill from the mail
                            // app can bring whitespace with it.
                            let digits = updated.filter(\.isNumber)
                            let trimmed = String(digits.prefix(6))
                            if trimmed != updated { code = trimmed }
                            if trimmed.count == 6 { focusedField = .password }
                        }
                }
                .resetField(timeOfDay: timeOfDay)

                HStack(spacing: 12) {
                    Image(systemName: "lock")
                        .foregroundStyle(timeOfDay.secondaryText)
                        .frame(width: 20)
                    SecureField("New password", text: $newPassword)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                        .onSubmit { confirm() }
                }
                .resetField(timeOfDay: timeOfDay)

                Text("Use at least 8 characters.")
                    .font(.caption)
                    .foregroundStyle(timeOfDay.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            problem

            primaryButton(
                "Reset Password",
                icon: "checkmark",
                enabled: code.count == 6 && newPassword.count >= 8,
                timeOfDay: timeOfDay,
                action: confirm
            )

            HStack(spacing: 5) {
                Text("Did not get it?")
                    .foregroundStyle(timeOfDay.secondaryText)
                Button("Send another") { sendCode() }
                    .fontWeight(.semibold)
                    .foregroundStyle(timeOfDay.accent)
                    .disabled(authentication.isResettingPassword)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Shared pieces

    private func title(
        eyebrow: String,
        headline: String,
        detail: String,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(timeOfDay.accent)
            Text(headline)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.65)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(timeOfDay.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var problem: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    Color.red.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14)
                )
        }
    }

    private func primaryButton(
        _ title: String,
        icon: String,
        enabled: Bool,
        timeOfDay: HomeTimeOfDay,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if authentication.isResettingPassword {
                    ProgressView().tint(Color.white)
                }
                Text(title)
                Spacer()
                Image(systemName: icon)
            }
            .font(.headline.weight(.bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || authentication.isResettingPassword)
        .opacity(enabled ? 1 : 0.42)
    }

#if DEBUG
    /// A launch flag, so both steps can be photographed on a simulator that
    /// has no way to tap anything. Debug builds only.
    private func applyPreviewFlag() {
        let flag = ProcessInfo.processInfo.environment["REPBASE_RESET_PREVIEW"]
        if flag == "code" {
            email = "you@example.com"
            step = .enteringCode
        }
    }
#endif

    // MARK: - Actions

    private func sendCode() {
        let address = email.trimmedReset
        guard address.contains("@") else { return }
        errorMessage = nil
        focusedField = nil

        Task {
            do {
                try await authentication.requestPasswordReset(email: address)
                email = address
                step = .enteringCode
                focusedField = .code
            } catch {
                errorMessage = error.userFacingMessage
            }
        }
    }

    private func confirm() {
        errorMessage = nil
        focusedField = nil

        Task {
            do {
                try await authentication.confirmPasswordReset(
                    email: email.trimmedReset,
                    code: code,
                    newPassword: newPassword
                )
                // The store is already signed in on the fresh token, so the
                // root view has swapped underneath this cover.
                dismiss()
            } catch {
                errorMessage = error.userFacingMessage
                // A refused code is the common case and it is worth another
                // try, so the field is cleared rather than the whole step.
                code = ""
                focusedField = .code
            }
        }
    }
}

private extension View {
    func resetField(timeOfDay: HomeTimeOfDay) -> some View {
        padding(.horizontal, 15)
            .frame(height: 55)
            .repbaseInsetSurface(cornerRadius: 14)
    }
}

private extension String {
    var trimmedReset: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
