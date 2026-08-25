//
//  PromptPickerView.swift
//  IOS Frontend
//
//  Swipe through the questions, answer one, add it to your profile.
//

import SwiftUI

/// One question at a time.
///
/// A page each rather than a list of twelve: choosing what to say about
/// yourself is easier when you are looking at one question than when you are
/// scanning a menu, and a full-width answer box invites more than a line does.
///
/// Saves as you go. "Add to profile" means it, so backing out of here does not
/// quietly discard an answer somebody just wrote.
struct PromptPickerView: View {
    @Environment(SocialProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selection: PromptQuestion = .whyITrain
    /// What is in the box for each question, keyed by question. Seeded from
    /// whatever is already on the profile so an existing answer can be edited
    /// rather than retyped.
    @State private var drafts: [String: String] = [:]
    @State private var hasSeeded = false

    private var maxPrompts: Int { 3 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            VStack(spacing: 0) {
                header(timeOfDay: timeOfDay)

                TabView(selection: $selection) {
                    ForEach(PromptQuestion.allCases) { question in
                        page(question, timeOfDay: timeOfDay)
                            .tag(question)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
        }
        .task {
            guard !hasSeeded else { return }
            for answer in store.prompts {
                drafts[answer.question] = answer.answer
            }
            // Open on the first unanswered question, so somebody adding their
            // second answer does not land on the one they already wrote.
            selection = PromptQuestion.allCases.first { question in
                store.prompts.allSatisfy { $0.question != question.rawValue }
            } ?? .whyITrain
            hasSeeded = true
        }
    }

    // MARK: - Chrome

    private func header(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(timeOfDay.canvasPrimaryText)

            VStack(alignment: .leading, spacing: 1) {
                Text("QUESTIONS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(timeOfDay.accent)
                Text("\(store.prompts.count) of \(maxPrompts) on your profile")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
            }

            Spacer()
        }
        .padding(.horizontal, RepbaseDesign.pageInset)
        .padding(.bottom, 4)
    }

    // MARK: - One question

    private func page(_ question: PromptQuestion, timeOfDay: HomeTimeOfDay) -> some View {
        let answered = store.prompts.first { $0.question == question.rawValue }
        let draft = drafts[question.rawValue] ?? ""
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    if answered != nil {
                        Label("On your profile", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(timeOfDay.accent)
                    }
                    Text(question.label)
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField(
                    question.hint,
                    text: binding(for: question),
                    axis: .vertical
                )
                .font(.system(size: 17))
                .lineLimit(4...8)
                .padding(14)
                .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(timeOfDay.border, lineWidth: 1)
                }

                HStack {
                    Text("\(draft.count)/140")
                        .font(.caption2)
                        .foregroundStyle(draft.count > 140 ? .red : timeOfDay.canvasSecondaryText)
                    Spacer()
                    if answered != nil {
                        Button("Remove", role: .destructive) { remove(question) }
                            .font(.caption.weight(.semibold))
                    }
                }

                if let message = blockingMessage(for: question, answered: answered) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    add(question)
                } label: {
                    HStack(spacing: 9) {
                        if store.isSaving { ProgressView().tint(.white) }
                        Text(answered == nil ? "Add to profile" : "Update answer")
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd(question, answered: answered, trimmed: trimmed))
                .opacity(canAdd(question, answered: answered, trimmed: trimmed) ? 1 : 0.42)

                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 10)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Rules

    /// Why the button is off, when it is off for a reason worth explaining.
    /// An empty box needs no explanation; a full profile does.
    private func blockingMessage(
        for question: PromptQuestion,
        answered: ProfilePromptAnswer?
    ) -> String? {
        guard answered == nil, store.prompts.count >= maxPrompts else { return nil }
        return "You have three answers on your profile. Remove one to add this."
    }

    private func canAdd(
        _ question: PromptQuestion,
        answered: ProfilePromptAnswer?,
        trimmed: String
    ) -> Bool {
        guard !store.isSaving, !trimmed.isEmpty, trimmed.count <= 140 else { return false }
        // A question already on the profile can always be rewritten; a new one
        // needs a free slot, which is the server's rule as well as this one.
        return answered != nil || store.prompts.count < maxPrompts
    }

    private func binding(for question: PromptQuestion) -> Binding<String> {
        Binding(
            get: { drafts[question.rawValue] ?? "" },
            set: { drafts[question.rawValue] = $0 }
        )
    }

    // MARK: - Writing

    /// Sends the whole set, because that is what the endpoint takes: replacing
    /// three rows is cheaper than reconciling them, and it cannot leave a
    /// fourth answer stranded.
    private func add(_ question: PromptQuestion) {
        let trimmed = (drafts[question.rawValue] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var next = store.prompts
        if let index = next.firstIndex(where: { $0.question == question.rawValue }) {
            next[index].answer = trimmed
        } else {
            next.append(
                ProfilePromptAnswer(
                    question: question.rawValue,
                    questionLabel: question.label,
                    answer: trimmed
                )
            )
        }
        Task { await store.savePrompts(next) }
    }

    private func remove(_ question: PromptQuestion) {
        let next = store.prompts.filter { $0.question != question.rawValue }
        drafts[question.rawValue] = ""
        Task { await store.savePrompts(next) }
    }
}
