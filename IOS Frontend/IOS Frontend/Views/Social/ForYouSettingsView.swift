//
//  ForYouSettingsView.swift
//  IOS Frontend
//
//  The reader's say over their For You page.
//

import SwiftUI

/// What For You has picked up about the reader, and what they can do about it.
///
/// In the order somebody needs them: what the page is working from -- so the
/// controls below are informed rather than blind -- then interests to add,
/// topics to hide, then the two big switches, personalisation off and
/// starting fresh. A topic is added or hidden, never both: choosing one takes
/// it out of the other in the same change.
///
/// Every change is saved as it is made, and the feed ranks again once the
/// sheet closes, so there is no Save button to forget and no stale page left
/// underneath it.
struct ForYouSettingsView: View {
    let timeOfDay: HomeTimeOfDay

    @Environment(SocialStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingFresh = false
    @State private var startedFresh = false
    /// Exercises are the long part of the list; they open on asking.
    @State private var showingAllExercises = false

    /// The server's own limit on added interests.
    private static let maxAdded = 30

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let preferences = store.forYouPreferences {
                        interestsSection(preferences)
                        addedTopicsSection(preferences)
                        hiddenTopicsSection(preferences)
                        personalisationSection(preferences)
                    } else if store.forYouPreferencesError == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }

                    if let message = store.forYouPreferencesError {
                        failure(message)
                    }
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Your For You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Start For You fresh?",
                isPresented: $confirmingFresh,
                titleVisibility: .visible
            ) {
                Button("Start fresh", role: .destructive) {
                    Task { startedFresh = await store.startForYouFresh() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your viewing history is deleted, and your past likes, comments and saves stop shaping For You. They stay on your posts and your profile.")
            }
            .task { await store.loadForYouPreferences() }
        }
        .presentationDetents([.large])
    }

    // MARK: - Sections

    private func interestsSection(_ preferences: ForYouPreferences) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("What it has picked up")

            if !preferences.personalized {
                note("Personalised recommendations are off, so nothing you do is being used.")
            } else if preferences.interests.isEmpty {
                note("Nothing yet. Like, save or stay on posts and it starts to learn.")
            } else {
                VStack(spacing: 12) {
                    ForEach(preferences.interests) { interest in
                        interestRow(interest)
                    }
                }
                note("Topics only. For You never keeps a list of whose posts you look at to show you here.")
            }
        }
    }

    private func interestRow(_ interest: ForYouInterest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(interest.label)
                    .font(.community(.subheadline, weight: .semibold))
                    .foregroundStyle(timeOfDay.primaryText)
                if interest.declared {
                    Text("You chose this")
                        .font(.community(.caption, weight: .semibold))
                        .foregroundStyle(timeOfDay.accent)
                }
                Spacer(minLength: 0)
            }
            ProgressView(value: interest.strength)
                .tint(timeOfDay.accent)
                .accessibilityLabel("\(interest.label): how much it counts")
                .accessibilityValue("\(Int((interest.strength * 100).rounded())) percent")
        }
        .accessibilityElement(children: .combine)
    }

    private func addedTopicsSection(_ preferences: ForYouPreferences) -> some View {
        let exercises = preferences.addableTopics.filter { $0.topic.hasPrefix("exercise:") }
        let shown = preferences.addableTopics.filter {
            showingAllExercises || !$0.topic.hasPrefix("exercise:") || preferences.isAdded($0.topic)
        }
        let full = preferences.addedTopics.count >= Self.maxAdded
        return VStack(alignment: .leading, spacing: 12) {
            heading("Show me more of")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(shown) { topic in
                    let added = preferences.isAdded(topic.topic)
                    chip(
                        topic,
                        on: added,
                        symbol: "plus",
                        hint: added ? "Stops counting it as one of your interests" : "Counts it as one of your interests"
                    ) {
                        Task { await store.setInterest(topic.topic, added: !added) }
                    }
                    .disabled(full && !added)
                }
            }
            if !showingAllExercises, !exercises.isEmpty {
                Button("Exercises…") { showingAllExercises = true }
                    .font(.community(.subheadline, weight: .semibold))
                    .foregroundStyle(timeOfDay.accent)
                    .buttonStyle(.plain)
            }
            note(full
                 ? "That is as many as can be added. Take one off to add another."
                 : "An interest you add counts as one you chose. Tap it again to take it off.")
        }
    }

    private func hiddenTopicsSection(_ preferences: ForYouPreferences) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Never show me")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(preferences.hideableTopics) { topic in
                    let hidden = preferences.isHidden(topic.topic)
                    chip(
                        topic,
                        on: hidden,
                        symbol: "eye.slash",
                        hint: hidden ? "Shows these posts again" : "Hides these posts from For You"
                    ) {
                        Task { await store.setTopic(topic.topic, hidden: !hidden) }
                    }
                }
            }
            note("A hidden topic is left out of For You entirely. Tap it again to bring it back.")
        }
    }

    /// A topic as a chip that is on or off. `symbol` marks it when on.
    private func chip(
        _ topic: ForYouTopic,
        on selected: Bool,
        symbol: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if selected {
                    Image(systemName: symbol)
                        .font(.community(size: 10, weight: .bold))
                }
                Text(topic.label)
                    .font(.community(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? timeOfDay.accent : timeOfDay.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                Capsule().fill(selected ? timeOfDay.accent.opacity(0.12) : Color.clear)
            )
            .overlay {
                Capsule().strokeBorder(
                    selected ? timeOfDay.accent : timeOfDay.secondaryText.opacity(0.35),
                    lineWidth: 1
                )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(store.isSavingForYouPreferences)
        .accessibilityLabel(topic.label)
        .accessibilityHint(hint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func personalisationSection(_ preferences: ForYouPreferences) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Personalisation")

            Toggle(isOn: Binding(
                get: { preferences.personalized },
                set: { value in Task { await store.setPersonalized(value) } }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Personalised recommendations")
                        .font(.community(.subheadline, weight: .semibold))
                        .foregroundStyle(timeOfDay.primaryText)
                    Text("When off, For You shows what is popular and new instead of using what you like, follow and watch. Topics you hid stay hidden.")
                        .font(.community(.footnote))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(timeOfDay.accent)
            .disabled(store.isSavingForYouPreferences)

            if startedFresh {
                note("Done. For You starts learning again from what you do next.")
            } else {
                Button {
                    confirmingFresh = true
                } label: {
                    Label("Start fresh…", systemImage: "arrow.counterclockwise")
                        .font(.community(.subheadline, weight: .semibold))
                        .foregroundStyle(RepbaseDesign.danger)
                }
                .buttonStyle(.plain)
                .disabled(store.isSavingForYouPreferences)
                .accessibilityHint("Deletes your viewing history and stops your past activity shaping For You")
            }
        }
    }

    // MARK: - Pieces

    private func heading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.community(.caption2, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(timeOfDay.accent)
            .accessibilityAddTraits(.isHeader)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.community(.footnote))
            .foregroundStyle(timeOfDay.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func failure(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(timeOfDay.accent)
            Text(message)
                .font(.community(.caption))
                .foregroundStyle(timeOfDay.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(timeOfDay.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }
}
