//
//  ProfileExpressionEditorView.swift
//  IOS Frontend
//
//  Choosing what a profile says: three questions, and three lifts.
//

import SwiftUI

/// Edits the answered questions and the featured lifts together.
///
/// One screen for both because they are the same decision from the reader's
/// side — what this profile says about the person — and splitting them would
/// mean two trips through settings to fill in one page.
struct ProfileExpressionEditorView: View {
    @Environment(SocialProfileStore.self) private var store
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(\.dismiss) private var dismiss

    /// Working copies. Nothing is sent until Save, so backing out of the
    /// screen leaves the profile as it was.
    @State private var answers: [ProfilePromptAnswer] = []
    @State private var featured: [Int] = []
    @State private var hasLoaded = false

    private var maxPrompts: Int { 3 }
    private var maxHighlights: Int { 3 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header(timeOfDay: timeOfDay)
                    promptsSection(timeOfDay: timeOfDay)
                    highlightsSection(timeOfDay: timeOfDay)

                    if let message = store.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    saveButton(timeOfDay: timeOfDay)
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
        }
        .task {
            // Seeded once. Re-seeding on every appearance would throw away
            // whatever was being typed when the keyboard resigned.
            guard !hasLoaded else { return }
            answers = store.prompts
            featured = store.highlights.map(\.exerciseID)
            hasLoaded = true
        }
    }

    // MARK: - Header

    private func header(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(timeOfDay.canvasPrimaryText)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR PROFILE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(timeOfDay.accent)
                Text("What people learn about you")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Prompts

    private func promptsSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Questions", detail: "Answer up to three.", timeOfDay: timeOfDay)

            ForEach(Array(answers.enumerated()), id: \.element.question) { index, answer in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(answer.questionLabel.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(timeOfDay.accent)
                        Spacer()
                        Button {
                            answers.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove this question")
                    }

                    TextField(
                        PromptQuestion(rawValue: answer.question)?.hint ?? "Your answer",
                        text: binding(for: index),
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .padding(12)
                    .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(timeOfDay.border, lineWidth: 1)
                    }

                    Text("\(answer.answer.count)/140")
                        .font(.caption2)
                        .foregroundStyle(
                            answer.answer.count > 140 ? Color.red : timeOfDay.canvasSecondaryText
                        )
                }
            }

            if answers.count < maxPrompts, !unusedQuestions.isEmpty {
                Menu {
                    ForEach(unusedQuestions) { question in
                        Button(question.label) {
                            answers.append(
                                ProfilePromptAnswer(
                                    question: question.rawValue,
                                    questionLabel: question.label,
                                    answer: ""
                                )
                            )
                        }
                    }
                } label: {
                    Label("Add a question", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(timeOfDay.accent)
                }
            }
        }
    }

    /// The questions not already answered, so the menu never offers a
    /// duplicate the server would refuse.
    private var unusedQuestions: [PromptQuestion] {
        let taken = Set(answers.map(\.question))
        return PromptQuestion.allCases.filter { !taken.contains($0.rawValue) }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { answers.indices.contains(index) ? answers[index].answer : "" },
            set: { if answers.indices.contains(index) { answers[index].answer = $0 } }
        )
    }

    // MARK: - Featured lifts

    private func highlightsSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(
                "Featured lifts",
                detail: "Show up to three. The numbers come from what you have logged, so there is nothing to type.",
                timeOfDay: timeOfDay
            )

            if availableExercises.isEmpty {
                Text("Add exercises to a workout first, and they can be featured here.")
                    .font(.subheadline)
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(availableExercises, id: \.id) { exercise in
                        let isOn = featured.contains(exercise.id)
                        Button {
                            toggle(exercise.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isOn ? timeOfDay.accent : timeOfDay.secondaryText)
                                Text(exercise.name)
                                    .font(.subheadline)
                                    .foregroundStyle(timeOfDay.primaryText)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // A fourth would be refused by the server, so it is
                        // not offered here.
                        .disabled(!isOn && featured.count >= maxHighlights)
                        .opacity(!isOn && featured.count >= maxHighlights ? 0.4 : 1)

                        if exercise.id != availableExercises.last?.id {
                            Divider().opacity(0.3)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(timeOfDay.border, lineWidth: 1)
                }
            }
        }
    }

    /// Every exercise in this person's plan, once each.
    ///
    /// Their own plan rather than the whole catalogue: featuring a lift you
    /// have never programmed is not a thing anyone wants to do, and the whole
    /// exercise table would be a thousand rows to scroll.
    private var availableExercises: [(id: Int, name: String)] {
        var seen: Set<Int> = []
        var found: [(id: Int, name: String)] = []
        for day in Weekday.allCases {
            for workout in workoutStore.workouts(on: day) {
                for exercise in workout.exercises {
                    guard let serverID = exercise.serverID,
                          seen.insert(serverID).inserted else { continue }
                    found.append((id: serverID, name: exercise.serverName ?? exercise.name))
                }
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func toggle(_ exerciseID: Int) {
        if let index = featured.firstIndex(of: exerciseID) {
            featured.remove(at: index)
        } else if featured.count < maxHighlights {
            featured.append(exerciseID)
        }
    }

    // MARK: - Pieces

    private func sectionTitle(
        _ title: String,
        detail: String,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text(detail)
                .font(.caption)
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var canSave: Bool {
        // An answered question with nothing in it would be refused, and the
        // refusal would name a question rather than the empty box on screen.
        answers.allSatisfy {
            !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.answer.count <= 140
        }
    }

    private func saveButton(timeOfDay: HomeTimeOfDay) -> some View {
        Button {
            Task {
                let trimmed = answers.map {
                    ProfilePromptAnswer(
                        question: $0.question,
                        questionLabel: $0.questionLabel,
                        answer: $0.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                let wrotePrompts = await store.savePrompts(trimmed)
                let wroteLifts = await store.saveHighlights(featured)
                if wrotePrompts && wroteLifts { dismiss() }
            }
        } label: {
            HStack(spacing: 9) {
                if store.isSaving { ProgressView().tint(.white) }
                Text("Save")
            }
            .font(.headline.weight(.bold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .disabled(store.isSaving || !canSave)
        .opacity(canSave ? 1 : 0.42)
    }
}
