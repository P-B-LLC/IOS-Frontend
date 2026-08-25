//
//  PromptPickerView.swift
//  IOS Frontend
//
//  One page: swipe through the questions, answer whichever is showing.
//

import SwiftUI

/// The questions on a single page.
///
/// Swiping moves through the questions; the answer box below stays put and
/// belongs to whichever one is showing. A page each meant the box scrolled
/// away with the question and the page count made twelve questions feel like
/// twelve steps, when it is one question and one answer.
struct PromptPickerView: View {
    @Environment(SocialProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selection: PromptQuestion = .whyITrain
    /// What is typed against each question, so swiping away and back does not
    /// lose an answer that has not been added yet.
    @State private var drafts: [String: String] = [:]
    @State private var hasSeeded = false
    @FocusState private var isWriting: Bool

    private var maxPrompts: Int { 3 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(timeOfDay: timeOfDay)
                    questionCarousel(timeOfDay: timeOfDay)
                    answerBox(timeOfDay: timeOfDay)
                    addButton(timeOfDay: timeOfDay)

                    if let error = store.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    answeredSoFar(timeOfDay: timeOfDay)
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
        }
        .task {
            guard !hasSeeded else { return }
            for answer in store.prompts {
                drafts[answer.question] = answer.answer
            }
            // Opens on the first unanswered question, so somebody adding their
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
    }

    // MARK: - The questions

    /// Only the question swipes. The box below is the same box throughout, so
    /// the page reads as one thing being filled in rather than twelve screens.
    private func questionCarousel(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TabView(selection: $selection) {
                ForEach(PromptQuestion.allCases) { question in
                    VStack(alignment: .leading, spacing: 7) {
                        if isAnswered(question) {
                            Label("On your profile", systemImage: "checkmark.circle.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(timeOfDay.accent)
                        }
                        Text(question.label)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(timeOfDay.canvasPrimaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.trailing, 8)
                    .tag(question)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 96)

            // Dots of our own: the built-in ones sit at the bottom of the
            // TabView, which here is the middle of the page.
            HStack(spacing: 5) {
                ForEach(PromptQuestion.allCases) { question in
                    Capsule()
                        .fill(
                            question == selection
                                ? timeOfDay.accent
                                : timeOfDay.canvasSecondaryText.opacity(0.3)
                        )
                        .frame(width: question == selection ? 16 : 5, height: 5)
                }
            }
            .animation(.easeOut(duration: 0.18), value: selection)

            Text("Swipe for another question")
                .font(.caption2)
                .foregroundStyle(timeOfDay.canvasSecondaryText)
        }
    }

    // MARK: - The answer

    private func answerBox(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField(
                selection.hint,
                text: binding(for: selection),
                axis: .vertical
            )
            .focused($isWriting)
            .font(.system(size: 17))
            .lineLimit(4...8)
            .padding(14)
            .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isWriting ? timeOfDay.accent : timeOfDay.border,
                        lineWidth: 1
                    )
            }

            HStack {
                Text("\(draft.count)/140")
                    .font(.caption2)
                    .foregroundStyle(draft.count > 140 ? .red : timeOfDay.canvasSecondaryText)
                Spacer()
                if isAnswered(selection) {
                    Button("Remove from profile", role: .destructive) {
                        remove(selection)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private func addButton(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isAnswered(selection), store.prompts.count >= maxPrompts {
                Text("You have three answers on your profile. Remove one to add this.")
                    .font(.caption)
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                isWriting = false
                add(selection)
            } label: {
                HStack(spacing: 9) {
                    if store.isSaving { ProgressView().tint(.white) }
                    Text(isAnswered(selection) ? "Update answer" : "Add to profile")
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .opacity(canAdd ? 1 : 0.42)
        }
    }

    /// What is already on the profile, so the three slots are visible without
    /// swiping the whole set to find them.
    @ViewBuilder
    private func answeredSoFar(timeOfDay: HomeTimeOfDay) -> some View {
        if !store.prompts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Rectangle()
                    .fill(timeOfDay.canvasBorder)
                    .frame(height: 1)

                Text("ON YOUR PROFILE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(timeOfDay.canvasSecondaryText)

                ForEach(store.prompts) { answer in
                    Button {
                        if let question = PromptQuestion(rawValue: answer.question) {
                            selection = question
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(answer.questionLabel.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(timeOfDay.accent)
                            Text(answer.answer)
                                .font(.subheadline)
                                .foregroundStyle(timeOfDay.canvasPrimaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Rules

    private var draft: String { drafts[selection.rawValue] ?? "" }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        guard !store.isSaving, !trimmedDraft.isEmpty, trimmedDraft.count <= 140
        else { return false }
        // An answer already on the profile can always be rewritten; a new one
        // needs a free slot, which is the server's rule as well as this one.
        return isAnswered(selection) || store.prompts.count < maxPrompts
    }

    private func isAnswered(_ question: PromptQuestion) -> Bool {
        store.prompts.contains { $0.question == question.rawValue }
    }

    private func binding(for question: PromptQuestion) -> Binding<String> {
        Binding(
            get: { drafts[question.rawValue] ?? "" },
            set: { drafts[question.rawValue] = $0 }
        )
    }

    // MARK: - Writing

    /// Sends the whole set, because that is what the endpoint takes: replacing
    /// three rows is cheaper than reconciling them and cannot strand a fourth.
    private func add(_ question: PromptQuestion) {
        let trimmed = trimmedDraft
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
