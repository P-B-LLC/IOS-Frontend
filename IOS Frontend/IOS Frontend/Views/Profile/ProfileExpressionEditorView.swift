//
//  ProfileExpressionEditorView.swift
//  IOS Frontend
//
//  Choosing what a profile says: three questions, and three lifts.
//

import SwiftUI

struct ProfileExpressionEditorView: View {
    @Environment(SocialProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var featured: Set<FeaturedLift> = []
    @State private var poundsDraft: [FeaturedLift: String] = [:]
    @State private var repsDraft: [FeaturedLift: String] = [:]
    @State private var focusedLift: FeaturedLift = .squat
    @State private var hasLoaded = false
    @State private var showingPrompts = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
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
        .fullScreenCover(isPresented: $showingPrompts) {
            NavigationStack { PromptPickerView() }
        }
        .task {
            guard !hasLoaded else { return }
            for lift in store.highlights {
                featured.insert(lift.lift)
                if lift.source == .manual {
                    poundsDraft[lift.lift] = lift.displayPounds.map(String.init) ?? ""
                    repsDraft[lift.lift] = lift.reps.map(String.init) ?? ""
                }
            }
            if let first = store.highlights.first?.lift { focusedLift = first }
            hasLoaded = true
        }
    }

    private func header(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.community(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(timeOfDay.canvasPrimaryText)
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 6) {
                Text("PROFILE DETAILS")
                    .font(.community(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(timeOfDay.accent)
                Text("Choose what stands out.")
                    .font(.community(size: 30, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                Text("A few details make your profile feel like you.")
                    .font(.community(.subheadline))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
        }
    }

    private func promptsSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Prompts", detail: "Tell others about you. Up to three.", timeOfDay: timeOfDay)
                Spacer()
                Text("\(store.prompts.count) OF 3")
                    .font(.community(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(timeOfDay.accent)
            }

            ForEach(store.prompts) { answer in
                VStack(alignment: .leading, spacing: 4) {
                    Text(answer.questionLabel.uppercased())
                        .font(.community(size: 9, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(timeOfDay.accent)
                    Text(answer.answer)
                        .font(.community(size: 17, weight: .semibold))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Capsule().fill(timeOfDay.accent).frame(width: 3)
                }
            }

            Button { showingPrompts = true } label: {
                HStack {
                    Text(store.prompts.isEmpty ? "Add prompts" : "Edit prompts")
                    Spacer()
                    Text("→")
                }
                .font(.community(.subheadline, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(timeOfDay.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private func liftsSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Featured lifts", detail: "Choose up to three.", timeOfDay: timeOfDay)

            HStack(spacing: 8) {
                ForEach(FeaturedLift.allCases) { lift in
                    liftPill(lift, timeOfDay: timeOfDay)
                }
            }

            if featured.contains(focusedLift) {
                liftEditorPanel(focusedLift, timeOfDay: timeOfDay)
            } else {
                Text("Choose a lift above to add it to your profile.")
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .padding(.vertical, 4)
            }
        }
    }

    private func liftPill(_ lift: FeaturedLift, timeOfDay: HomeTimeOfDay) -> some View {
        let isOn = featured.contains(lift)
        let isFocused = focusedLift == lift

        return Button {
            focusedLift = lift
            if !isOn { featured.insert(lift) }
        } label: {
            HStack(spacing: 6) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.community(size: 10, weight: .bold))
                }
                Text(lift.label.replacingOccurrences(of: " Press", with: ""))
                    .lineLimit(1)
            }
            .font(.community(.caption, weight: .bold))
            .foregroundStyle(
                isFocused && isOn
                    ? timeOfDay.onPrimaryAction
                    : (isOn ? timeOfDay.accent : timeOfDay.canvasSecondaryText)
            )
            .frame(maxWidth: .infinity, minHeight: 42)
            .background {
                RoundedRectangle(cornerRadius: 13)
                    .fill(
                        isFocused && isOn
                            ? timeOfDay.primaryActionSurface
                            : (isOn ? timeOfDay.accent.opacity(0.11) : timeOfDay.selectorSurface)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(isOn ? timeOfDay.accent.opacity(0.35) : timeOfDay.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "Shown on profile" : "Not shown on profile")
    }

    private func liftEditorPanel(_ lift: FeaturedLift, timeOfDay: HomeTimeOfDay) -> some View {
        let logged = store.highlights.first { $0.lift == lift && $0.source == .logged }

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(lift.label.uppercased()) · SHOWN ON PROFILE")
                        .font(.community(size: 9, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(timeOfDay.accent)
                    Text(logged == nil ? "Manual" : "Best logged set")
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(timeOfDay.accent)
            }

            if let logged, let summary = logged.setSummary {
                HStack(alignment: .lastTextBaseline) {
                    Text(summary)
                        .font(.community(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(timeOfDay.primaryText)
                    Spacer()
                    if let estimate = logged.estimatedOneRepMaxPounds {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("ESTIMATED 1RM")
                                .font(.community(size: 8, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(timeOfDay.secondaryText)
                            Text("\(estimate) lb")
                                .font(.community(.subheadline, weight: .bold))
                                .foregroundStyle(timeOfDay.primaryText)
                        }
                    }
                }
                Text("This uses your best logged set and updates as you train.")
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.secondaryText)
            } else {
                manualFields(lift, timeOfDay: timeOfDay)
            }

            HStack {
                Label("Use your best logged set when available", systemImage: "arrow.triangle.2.circlepath")
                    .font(.community(.caption2))
                    .foregroundStyle(timeOfDay.secondaryText)
                Spacer(minLength: 8)
                Text(logged == nil ? "MANUAL" : "AUTO")
                    .font(.community(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(timeOfDay.accent)
            }

            Button(role: .destructive) { featured.remove(lift) } label: {
                Text("Remove from profile")
                    .font(.community(.caption, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            timeOfDay.accent.opacity(timeOfDay.usesDarkAppearance ? 0.09 : 0.07),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(timeOfDay.border, lineWidth: 1)
        }
    }

    private func manualFields(_ lift: FeaturedLift, timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing logged for this yet. Enter your best set.")
                .font(.community(.caption))
                .foregroundStyle(timeOfDay.secondaryText)
            HStack(spacing: 18) {
                numberField("Weight", unit: "lb", text: poundsBinding(lift), timeOfDay: timeOfDay)
                numberField("Reps", unit: "", text: repsBinding(lift), timeOfDay: timeOfDay)
            }
        }
    }

    private func numberField(
        _ title: String,
        unit: String,
        text: Binding<String>,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.community(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(timeOfDay.secondaryText)
            HStack(spacing: 4) {
                TextField("0", text: text)
                    .keyboardType(.numberPad)
                    .font(.community(.title3, weight: .bold))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
            }
            Rectangle().fill(timeOfDay.border).frame(height: 1)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Your profile updates as soon as these changes are saved.")
                .font(.community(.caption))
                .foregroundStyle(timeOfDay.canvasSecondaryText)

            if let incomplete = incompleteLift {
                Text("Give \(incomplete.label) both a weight and a rep count, or leave both empty.")
                    .font(.community(.caption))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    if await store.saveHighlights(payload) { dismiss() }
                }
            } label: {
                HStack(spacing: 9) {
                    if store.isSaving { ProgressView().tint(timeOfDay.onPrimaryAction) }
                    Text("Save changes")
                    Spacer()
                    Text("→")
                }
                .font(.community(.headline, weight: .bold))
                .foregroundStyle(timeOfDay.onPrimaryAction)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(timeOfDay.primaryActionSurface, in: RoundedRectangle(cornerRadius: 17))
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
                .font(.community(size: 20, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text(detail)
                .font(.community(.caption))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
