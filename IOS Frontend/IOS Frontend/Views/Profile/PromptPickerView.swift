//
//  PromptPickerView.swift
//  IOS Frontend
//
//  Three slots, a library to pick from, and a page to write the answer on.
//

import SwiftUI

/// The three answers on a profile, as slots to fill.
///
/// Slots first, rather than a list of questions: what somebody is deciding is
/// "what do my three say about me", and three cards make that the shape of the
/// screen. An empty one is an invitation; a filled one is editable in place.
///
/// Everything saves as it happens. There is no Done button to lose work behind.
struct PromptPickerView: View {
    @Environment(SocialProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Which slot is being filled, if the library is open.
    @State private var choosingForSlot: SlotIndex?
    /// The question being answered, if the writing page is open.
    @State private var writing: PromptQuestion?

    private var maxPrompts: Int { 3 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(timeOfDay: timeOfDay)

                    ForEach(0..<maxPrompts, id: \.self) { index in
                        slot(index, timeOfDay: timeOfDay)
                    }

                    if let error = store.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Prompts show on your profile under About. Tap one to rewrite it, or swap it for a different prompt.")
                        .font(.caption)
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
        }
        .sheet(item: $choosingForSlot) { slot in
            NavigationStack {
                PromptLibraryView(
                    taken: Set(store.prompts.map(\.question)),
                    replacing: answer(at: slot.value)?.question
                ) { question in
                    choosingForSlot = nil
                    // Straight into writing it, the way picking a question
                    // implies wanting to answer it.
                    writing = question
                }
            }
        }
        .sheet(item: $writing) { question in
            NavigationStack {
                PromptAnswerView(question: question)
            }
        }
    }

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
                Text("PROMPTS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(timeOfDay.accent)
                Text("Tell others about you")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
            }

            Spacer()
        }
    }

    /// One slot: an answer to tap, or an invitation to fill it.
    private func slot(_ index: Int, timeOfDay: HomeTimeOfDay) -> some View {
        Group {
            if let answered = answer(at: index) {
                Button {
                    writing = PromptQuestion(rawValue: answered.question)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(answered.questionLabel.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(timeOfDay.accent)
                            Spacer(minLength: 8)
                            Image(systemName: "pencil")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(timeOfDay.secondaryText)
                        }
                        Text(answered.answer)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(timeOfDay.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(timeOfDay.border, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Choose a different prompt", systemImage: "arrow.triangle.2.circlepath") {
                        choosingForSlot = SlotIndex(value: index)
                    }
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        remove(answered)
                    }
                }
            } else {
                Button {
                    choosingForSlot = SlotIndex(value: index)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(timeOfDay.accent)
                        Text("Select a prompt")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background {
                        // Dashed, so an empty slot reads as somewhere to write
                        // rather than as a card that failed to load.
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(
                                timeOfDay.canvasSecondaryText.opacity(0.35),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                            )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func answer(at index: Int) -> ProfilePromptAnswer? {
        store.prompts.indices.contains(index) ? store.prompts[index] : nil
    }

    private func remove(_ answered: ProfilePromptAnswer) {
        let next = store.prompts.filter { $0.question != answered.question }
        Task { await store.savePrompts(next) }
    }
}

/// A slot number that can present a sheet. `sheet(item:)` wants Identifiable
/// and a bare Int is not — and slot 0 must present, so an optional Int with
/// `item:` would not do either.
private struct SlotIndex: Identifiable {
    let value: Int
    var id: Int { value }
}

// MARK: - The library

/// Every question, in sections, with a search box.
///
/// Browsable rather than a picker wheel: choosing what to say about yourself
/// is worth reading a few options for, and the sections let somebody go
/// straight to the part of their life they want to talk about.
struct PromptLibraryView: View {
    @Environment(\.dismiss) private var dismiss

    /// Questions already answered. Shown but not selectable, so it is obvious
    /// why one is missing rather than the list quietly being shorter.
    let taken: Set<String>
    /// The question this slot currently holds, which may be re-picked.
    var replacing: String?
    let onSelect: (PromptQuestion) -> Void

    @State private var search = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                    ForEach(PromptCategory.allCases) { category in
                        let questions = matching(category)
                        if !questions.isEmpty {
                            Section {
                                VStack(spacing: 0) {
                                    ForEach(questions) { question in
                                        row(question, timeOfDay: timeOfDay)
                                        if question != questions.last {
                                            Divider().opacity(0.25).padding(.leading, 16)
                                        }
                                    }
                                }
                                .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(timeOfDay.border, lineWidth: 1)
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.rawValue)
                                        .font(.system(size: 19, weight: .bold))
                                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                                    Text(category.blurb)
                                        .font(.caption)
                                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 6)
                            }
                        }
                    }

                    if PromptCategory.allCases.allSatisfy({ matching($0).isEmpty }) {
                        Text("No prompt matches “\(search)”.")
                            .font(.subheadline)
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .searchable(text: $search, prompt: "Search prompts")
            .navigationTitle("Choose a prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .homeTimeScreen(timeOfDay)
        }
    }

    private func matching(_ category: PromptCategory) -> [PromptQuestion] {
        PromptQuestion.allCases.filter { $0.category == category && $0.matches(search) }
    }

    private func row(_ question: PromptQuestion, timeOfDay: HomeTimeOfDay) -> some View {
        let isTaken = taken.contains(question.rawValue) && question.rawValue != replacing

        return Button {
            onSelect(question)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(question.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(timeOfDay.primaryText)
                        .multilineTextAlignment(.leading)
                    Text(question.hint)
                        .font(.caption2)
                        .foregroundStyle(timeOfDay.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isTaken {
                    Text("ADDED")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(timeOfDay.accent)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isTaken)
        .opacity(isTaken ? 0.45 : 1)
    }
}

// MARK: - Writing the answer

/// One question, one answer, one button.
struct PromptAnswerView: View {
    @Environment(SocialProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let question: PromptQuestion

    @State private var draft = ""
    @State private var hasSeeded = false
    @FocusState private var isWriting: Bool

    private var limit: Int { 140 }

    private var existing: ProfilePromptAnswer? {
        store.prompts.first { $0.question == question.rawValue }
    }

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !store.isSaving && !trimmed.isEmpty && trimmed.count <= limit
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(question.label)
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField(question.hint, text: $draft, axis: .vertical)
                        .focused($isWriting)
                        .font(.system(size: 17))
                        .lineLimit(4...10)
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
                        Text("\(draft.count)/\(limit)")
                            .font(.caption2)
                            .foregroundStyle(
                                draft.count > limit ? .red : timeOfDay.canvasSecondaryText
                            )
                        Spacer()
                        if existing != nil {
                            Button("Remove from profile", role: .destructive) {
                                remove()
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }

                    if let error = store.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button { save() } label: {
                        HStack(spacing: 9) {
                            if store.isSaving { ProgressView().tint(.white) }
                            Text(existing == nil ? "Add to profile" : "Save answer")
                        }
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.42)
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? "Your answer" : "Edit answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .homeTimeScreen(timeOfDay)
        }
        .task {
            guard !hasSeeded else { return }
            draft = existing?.answer ?? ""
            hasSeeded = true
            // The keyboard is the point of this screen.
            isWriting = true
        }
    }

    /// Sends the whole set, because that is what the endpoint takes: three
    /// rows are cheaper to replace than to reconcile, and replacing cannot
    /// strand a fourth answer where nobody can see it.
    private func save() {
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
        Task {
            if await store.savePrompts(next) { dismiss() }
        }
    }

    private func remove() {
        let next = store.prompts.filter { $0.question != question.rawValue }
        Task {
            if await store.savePrompts(next) { dismiss() }
        }
    }
}
