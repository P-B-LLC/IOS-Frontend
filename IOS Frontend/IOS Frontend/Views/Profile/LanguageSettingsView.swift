import SwiftUI

/// Settings > Language: follow the iPhone, or pick one of Rytivo's languages.
///
/// The choice applies as soon as it is tapped, on this screen included, and
/// survives relaunching. System Default is a row of its own rather than the
/// absence of a choice, so going back to the iPhone's language is one tap
/// instead of finding whichever language that happens to be.
struct LanguageSettingsView: View {
    private let localization = AppLocalization.shared

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current
        let preference = localization.preference

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                RepbaseScreenHeader(
                    eyebrow: "Language",
                    title: "Your language.",
                    detail: "Rytivo uses your iPhone's language when it can. Choose another here, and it stays until you change it."
                )

                VStack(spacing: 0) {
                    optionRow(
                        isSelected: preference == .system,
                        select: .system
                    ) {
                        Text("System Default")
                            .font(.community(.headline))
                            .foregroundStyle(.primary)
                        Group {
                            if let systemLanguage = localization.systemLanguage {
                                Text("Matches your iPhone · \(displayName(of: systemLanguage))")
                            } else {
                                Text("Matches your iPhone")
                            }
                        }
                        .font(.community(.caption))
                        .foregroundStyle(.secondary)
                    }

                    ForEach(AppLanguage.allCases) { language in
                        Divider()
                        optionRow(
                            isSelected: preference == .language(language),
                            select: .language(language)
                        ) {
                            Text(nativeName(of: language))
                                .font(.community(.headline))
                                .foregroundStyle(.primary)
                            Text(displayName(of: language))
                                .font(.community(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text("Permission requests from iOS switch language the next time Rytivo opens.")
                    .font(.community(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(RepbaseDesign.pageInset)
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .homeTimeScreen(timeOfDay)
#if DEBUG
        // Picks a language a few seconds after the screen appears, the way a
        // tap would, so switching without a relaunch can be watched from a
        // script. "system" goes back to System Default.
        .task {
            guard let raw = ProcessInfo.processInfo.environment["REPBASE_LANGUAGE_SWITCH"] else { return }
            try? await Task.sleep(for: .seconds(4))
            localization.select(raw == "system" ? .system : AppLanguage(rawValue: raw).map { .language($0) } ?? .system)
        }
#endif
    }

    private func optionRow<Label: View>(
        isSelected: Bool,
        select preference: AppLanguagePreference,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            guard !isSelected else { return }
            withAnimation(.snappy(duration: 0.2)) {
                localization.select(preference)
            }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    label()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "checkmark")
                    .font(.community(size: 15, weight: .bold))
                    .foregroundStyle(RepbasePalette.caramel)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The language's own name, tagged with that language so VoiceOver reads
    /// "Deutsch" in German rather than spelling it out in English.
    private func nativeName(of language: AppLanguage) -> AttributedString {
        var name = AttributedString(language.nativeName)
        name.languageIdentifier = language.rawValue
        return name
    }

    /// The language's name in whatever language the screen is in now.
    ///
    /// Capitalized at the start because it sits alone on a line: Spanish,
    /// French and Russian write language names in lower case mid-sentence.
    private func displayName(of language: AppLanguage) -> String {
        let locale = localization.locale
        guard let name = locale.localizedString(forIdentifier: language.rawValue) else {
            return language.nativeName
        }
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }
}
