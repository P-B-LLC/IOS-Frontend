//
//  ProfileExpressionEditorView.swift
//  IOS Frontend
//
//  Choosing what a profile says: three questions, and three lifts.
//

import SwiftUI

/// The featured lifts, and the way through to the questions.
///
/// The questions live on their own page because answering one is a different
/// kind of task from ticking a lift — it wants the whole screen and one
/// question at a time. This page keeps what is left: which of the three lifts
/// to show, and what each will say.
struct ProfileExpressionEditorView: View {
    @Environment(SocialProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Working copies, keyed by lift. Nothing is sent until Save.
    @State private var featured: Set<FeaturedLift> = []
    @State private var poundsDraft: [FeaturedLift: String] = [:]
    @State private var repsDraft: [FeaturedLift: String] = [:]
    @State private var hasLoaded = false
    @State private var showingPrompts = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header(timeOfDay: timeOfDay)
                    promptsSection(timeOfDay: timeOfDay)
                    liftsSection(timeOfDay: timeOfDay)

                    if let message = store.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.community(.footnote))
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
        .sheet(isPresented: $showingPrompts) {
            NavigationStack { PromptPickerView() }
        }
        .task {
            // Seeded once, or typing would be thrown away every time the
            // keyboard resigned.
            guard !hasLoaded else { return }
            for lift in store.highlights {
                featured.insert(lift.lift)
                if lift.source == .manual {
                    poundsDraft[lift.lift] = lift.displayPounds.map(String.init) ?? ""
                    repsDraft[lift.lift] = lift.reps.map(String.init) ?? ""
                }
            }
            hasLoaded = true
        }
    }

    // MARK: - Header

    private func header(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.community(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(timeOfDay.canvasPrimaryText)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR PROFILE")
                    .font(.community(size: 10, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(timeOfDay.accent)
                Text("What people learn about you")
                    .font(.community(size: 28, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Prompts

    private func promptsSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(
                "Prompts",
                detail: "Tell others about you. Up to three.",
                timeOfDay: timeOfDay
            )

            ForEach(store.prompts) { answer in
                VStack(alignment: .leading, spacing: 3) {
                    Text(answer.questionLabel.uppercased())
                        .font(.community(size: 9, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(timeOfDay.accent)
                    Text(answer.answer)
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                showingPrompts = true
            } label: {
                Label(
                    store.prompts.isEmpty ? "Add prompts" : "Change your prompts",
                    systemImage: "text.bubble"
                )
                .font(.community(.subheadline, weight: .semibold))
                .foregroundStyle(timeOfDay.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Featured lifts

    private func liftsSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(
                "Featured lifts",
                detail: "Bench, squat and deadlift. Each one shows your heaviest logged set, or the numbers you enter here.",
                timeOfDay: timeOfDay
            )

            VStack(spacing: 0) {
                ForEach(FeaturedLift.allCases) { lift in
                    liftRow(lift, timeOfDay: timeOfDay)
                    if lift != FeaturedLift.allCases.last {
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

    private func liftRow(_ lift: FeaturedLift, timeOfDay: HomeTimeOfDay) -> some View {
        let logged = store.highlights.first { $0.lift == lift && $0.source == .logged }
        let isOn = featured.contains(lift)

        return VStack(alignment: .leading, spacing: 9) {
            Button {
                if isOn { featured.remove(lift) } else { featured.insert(lift) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? timeOfDay.accent : timeOfDay.secondaryText)
                    Text(lift.label)
                        .font(.community(.subheadline, weight: .semibold))
                        .foregroundStyle(timeOfDay.primaryText)
                    Spacer(minLength: 0)
                    if let logged, let summary = logged.setSummary {
                        Text(summary)
                            .font(.community(.subheadline, weight: .bold))
                            .foregroundStyle(timeOfDay.primaryText)
                    }
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOn {
                if let logged, let summary = logged.setSummary {
                    // Nothing to type: the number is already better evidence
                    // than anything that could be entered here, and it keeps
                    // itself up to date.
                    Label(
                        "\(summary) from \(logged.exerciseName ?? "your log"). This updates itself as you train.",
                        systemImage: "checkmark.seal"
                    )
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                } else {
                    manualFields(lift, timeOfDay: timeOfDay)
                }
            }
        }
    }

    private func manualFields(_ lift: FeaturedLift, timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Nothing logged for this yet. Enter your best set.")
                .font(.community(.caption))
                .foregroundStyle(timeOfDay.secondaryText)

            HStack(spacing: 10) {
                numberField("Weight", unit: "lb", text: poundsBinding(lift), timeOfDay: timeOfDay)
                numberField("Reps", unit: "", text: repsBinding(lift), timeOfDay: timeOfDay)
            }
        }
        .padding(.bottom, 12)
    }

    private func numberField(
        _ title: String,
        unit: String,
        text: Binding<String>,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.community(size: 8, weight: .bold))
                .foregroundStyle(timeOfDay.secondaryText)
            HStack(spacing: 4) {
                TextField("0", text: text)
                    .keyboardType(.numberPad)
                    .font(.community(.subheadline, weight: .semibold))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 40)
            .background(timeOfDay.selectorSurface, in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(timeOfDay.border, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func poundsBinding(_ lift: FeaturedLift) -> Binding<String> {
        Binding(
            get: { poundsDraft[lift] ?? "" },
            set: { poundsDraft[lift] = $0.filter(\.isNumber) }
        )
    }

    private func repsBinding(_ lift: FeaturedLift) -> Binding<String> {
        Binding(
            get: { repsDraft[lift] ?? "" },
            set: { repsDraft[lift] = $0.filter(\.isNumber) }
        )
    }

    // MARK: - Saving

    /// What will be sent. A lift with a logged set goes out bare, because the
    /// server reads the set itself; one without goes out with whatever pair
    /// was typed, and only if both halves are there.
    private var payload: [HighlightLift] {
        FeaturedLift.allCases.filter(featured.contains).map { lift in
            let logged = store.highlights.first { $0.lift == lift && $0.source == .logged }
            if logged != nil {
                return HighlightLift(
                    lift: lift, label: lift.label, source: .none,
                    weightKilograms: nil, reps: nil,
                    estimatedOneRepMaxKilograms: nil, performedAt: nil, exerciseName: nil
                )
            }
            let pounds = Int(poundsDraft[lift] ?? "")
            let reps = Int(repsDraft[lift] ?? "")
            guard let pounds, let reps, pounds > 0, reps > 0 else {
                return HighlightLift(
                    lift: lift, label: lift.label, source: .none,
                    weightKilograms: nil, reps: nil,
                    estimatedOneRepMaxKilograms: nil, performedAt: nil, exerciseName: nil
                )
            }
            return HighlightLift(
                lift: lift, label: lift.label, source: .manual,
                weightKilograms: HighlightLift.kilograms(fromPounds: pounds),
                reps: reps,
                estimatedOneRepMaxKilograms: nil, performedAt: nil, exerciseName: nil
            )
        }
    }

    /// A half-filled pair is the one thing the server will refuse, so it is
    /// caught here where the empty box is on screen to point at.
    private var incompleteLift: FeaturedLift? {
        FeaturedLift.allCases.filter(featured.contains).first { lift in
            guard store.highlights.first(where: { $0.lift == lift && $0.source == .logged }) == nil
            else { return false }
            let hasPounds = !(poundsDraft[lift] ?? "").isEmpty
            let hasReps = !(repsDraft[lift] ?? "").isEmpty
            return hasPounds != hasReps
        }
    }

    private func saveButton(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let incomplete = incompleteLift {
                Text("Give \(incomplete.label) both a weight and a rep count, or leave both empty.")
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    if await store.saveHighlights(payload) { dismiss() }
                }
            } label: {
                HStack(spacing: 9) {
                    if store.isSaving { ProgressView().tint(.white) }
                    Text("Save")
                }
                .font(.community(.headline, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .disabled(store.isSaving || incompleteLift != nil)
            .opacity(incompleteLift == nil ? 1 : 0.42)
        }
    }

    private func sectionTitle(
        _ title: String,
        detail: String,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.community(size: 19, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text(detail)
                .font(.community(.caption))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
