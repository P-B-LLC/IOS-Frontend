import Foundation
import SwiftUI
import UIKit

/// Logging an activity that already happened, offered where there is a day
/// to log it on.
struct ActivityLogging {
    /// When a logged activity finished, unless changed: now, or the same time
    /// of day on the day being planned.
    let defaultEnd: Date
    /// The day it is logged on, up to now: a session filed under Tuesday
    /// has to have happened on Tuesday.
    let finishedRange: ClosedRange<Date>
    let distanceUnit: ActivityLogDraft.DistanceUnit
    let onLog: (ActivityLogEntry) -> Void
}

/// The same draft travels through every step; navigation never writes a plan.
///
/// A strength activity is planned: name, exercises, review. Anything else is
/// usually being written down after it happened, so its second step asks
/// about it -- how long, how hard -- and saves it straight to history, with
/// planning it for later one switch away.
struct GuidedWorkoutBuilder: View {
    enum Stage: Hashable { case identity, exercises, details, review }
    enum DetailsMode: Hashable { case log, plan }
    @Binding var draft: Workout
    let suggestions: [WorkoutSummary]
    let startsAtReview: Bool
    let isSaving: Bool
    let onSave: () -> Void
    /// Nil where only plans are made: the library and rotations.
    var logging: ActivityLogging? = nil
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var stage: Stage = .identity
    @State private var initialized = false
    @State private var reusing = false
    @State private var removed: (exercise: Exercise, index: Int)?
    @State private var reordering = false
    @State private var log = ActivityLogDraft(activity: .weightlifting)
    @State private var detailsMode: DetailsMode = .log
    @State private var logProblem: ActivityLogDraft.Problem?
    private let phase = WorkoutVisualPhase.prepare

    private var isStrength: Bool { draft.activity.usesSets }
    private var logsActivity: Bool { !isStrength && logging != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                intro
                switch stage {
                case .identity: identity
                case .exercises: exercisePicker
                case .details: details
                case .review: review
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        // Each step starts at its heading, even after scrolling a long catalog.
        .id(stage)
        // Out of the way while typing: on the exercise search it sat on top of
        // the keyboard, over the results.
        .safeAreaInset(edge: .bottom) {
            if stage == .exercises { HiddenWhileKeyboardShows { footer } } else { footer }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(stage == .identity ? "Cancel" : "Back") {
                    switch stage {
                    case .identity: dismiss()
                    case .exercises, .details: stage = .identity
                    case .review: stage = isStrength ? .exercises : .identity
                    }
                }.disabled(isSaving)
            }
        }
        .repbaseScreen(.prepare)
        .disabled(isSaving)
        .sensoryFeedback(.selection, trigger: draft.exercises.count)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            for i in draft.exercises.indices where draft.exercises[i].sets < 1 {
                draft.exercises[i].sets = 1
            }
            if startsAtReview { stage = .review }
            if let logging {
                log = ActivityLogDraft(activity: draft.activity, endedAt: logging.defaultEnd)
                log.distanceUnit = logging.distanceUnit
            } else {
                log = ActivityLogDraft(activity: draft.activity)
            }
        }
        .onChange(of: draft.activity) { _, activity in
            // Only what still applies carries over: a yoga style must not
            // follow somebody who changed their mind to tennis.
            log = log.switching(to: activity)
            logProblem = nil
        }
        .sheet(isPresented: $reusing) { reuseSheet }
        .sheet(isPresented: $reordering) { DraftReorderSheet(exercises: $draft.exercises) }
        .onChange(of: draft.exercises) { _, _ in
            // Recovery can arrive after onAppear. Keep the visible minimum and
            // the value that will actually be saved consistent.
            for i in draft.exercises.indices where draft.exercises[i].sets < 1 { draft.exercises[i].sets = 1 }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                progressStep(stepTitle(.identity), number: 1, step: .identity)
                if isStrength {
                    progressStep(stepTitle(.exercises), number: 2, step: .exercises)
                    progressStep(stepTitle(.review), number: 3, step: .review)
                } else if logsActivity {
                    progressStep(stepTitle(.details), number: 2, step: .details)
                } else {
                    progressStep(stepTitle(.review), number: 2, step: .review)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(stageNumber) of \(isStrength ? 3 : 2): \(stepTitle(stage))")

            Text(introText)
                .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stageNumber: Int {
        switch stage {
        case .identity: 1
        case .exercises, .details: 2
        case .review: isStrength ? 3 : 2
        }
    }

    private var navigationTitle: LocalizedStringKey {
        switch stage {
        case .identity: "New workout"
        case .exercises: "Add exercises"
        case .details: detailsMode == .log ? "Log activity" : "Plan activity"
        case .review: "Review workout"
        }
    }

    private var introText: LocalizedStringKey {
        switch stage {
        case .identity: "Choose what you’re doing and name it. Add only what you want to track."
        case .exercises: "Every exercise you add appears in your workout below."
        case .details:
            detailsMode == .log
                ? "Only how long it took is needed. Add anything else you know."
                : "Save it to this day, then start it when you begin."
        case .review:
            draft.tracksDistance
                ? "Review your workout, then save it when you’re ready."
                : "Tap Reorder to drag exercises into a new order. Tap a set to change its kind."
        }
    }

    private func stepTitle(_ step: Stage) -> String {
        switch step {
        case .identity: return String(localized: "Name", bundle: .app, locale: .app, comment: "Workout builder step: naming the workout")
        case .exercises: return String(localized: "Exercises", bundle: .app, locale: .app, comment: "Workout builder step: choosing exercises")
        case .details: return String(localized: "Details", bundle: .app, locale: .app, comment: "Workout builder step: how long and how hard an activity was")
        case .review: return String(localized: "Review", bundle: .app, locale: .app, comment: "Workout builder step: checking before saving")
        }
    }

    private func progressStep(_ title: String, number: Int, step: Stage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(number <= stageNumber ? phase.accent : phase.cardBorder)
                .frame(height: 3)
            Text("\(number)  \(title)")
                .font(.community(.caption, weight: stage == step ? .bold : .medium))
                .foregroundStyle(stage == step ? phase.primaryText : phase.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                eyebrow("WORKOUT NAME")
                TextField(isStrength ? "e.g. Push day" : LocalizedStringKey(draft.activity.title), text: $draft.name)
                    .font(.community(.headline)).textInputAutocapitalization(.words)
                    .padding(16).workoutOutline()
                Text(isStrength ? "Make it yours—or name it before saving." : "Optional. Left blank, it’s saved as \(draft.activity.title).")
                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                if hasDuplicateSavedName { duplicateNameNotice }
            }
            VStack(alignment: .leading, spacing: 12) {
                eyebrow("HOW ARE YOU MOVING?")
                ActivityPicker(selection: $draft.activity, phase: phase)
                Text(draft.activity.trackingSummary)
                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Button { reusing = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Use your saved workouts").font(.community(.subheadline, weight: .bold))
                            Text("Choose a saved plan to copy its exercises").font(.community(.caption2)).foregroundStyle(phase.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward").font(.caption)
                    }.padding(14).workoutOutline()
                }.buttonStyle(.plain).disabled(suggestions.isEmpty)
                if suggestions.isEmpty { Text("Your saved workouts will appear here.").font(.community(.caption)).foregroundStyle(phase.secondaryText) }
            }
        }
    }

    private var exercisePicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            selectedExercises
            ExerciseCatalogPicker(
                isSelected: { option in draft.exercises.contains { option.matches(serverID: $0.serverID, name: $0.name) } },
                onToggle: toggle,
                onCreate: addCustomExercise,
                phase: phase,
                pendingCustomNames: draft.exercises.filter { $0.serverID == nil }.map(\.name)
            )
        }
    }

    private var selectedExercises: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Your workout").font(.community(.headline))
                Spacer(minLength: 0)
                Text("\(draft.exercises.count) added")
                    .font(.community(.caption, weight: .bold))
                    .foregroundStyle(phase.accent)
            }
            if !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(draft.name).font(.community(.title3, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Draft · not saved yet")
                .font(.community(.caption)).foregroundStyle(phase.secondaryText)

            if draft.exercises.isEmpty {
                Label("No exercises added. Choose one below to start.", systemImage: "plus.circle")
                    .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { index, exercise in
                    HStack(alignment: .center, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.community(.caption, weight: .bold).monospacedDigit())
                            .foregroundStyle(phase.accent)
                            .frame(minWidth: 20)
                        Text(exercise.displayName).font(.community(.subheadline, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            draft.exercises.removeAll { $0.id == exercise.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 20))
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain).foregroundStyle(phase.secondaryText)
                        .accessibilityLabel("Remove \(exercise.displayName) from your workout")
                    }
                    if index < draft.exercises.count - 1 { Divider() }
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(colors: [phase.accent.opacity(0.09), phase.surfaceStart], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(phase.accent.opacity(0.25), lineWidth: 1) }
        .accessibilityIdentifier("workout-builder-selected-exercises")
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                eyebrow("YOUR WORKOUT · READY TO REVIEW")
                TextField("Workout name", text: $draft.name, axis: .vertical)
                    .font(.community(.title2, weight: .bold))
                    .textInputAutocapitalization(.words).accessibilityLabel("Workout name")
                Text(draft.tracksDistance ? "\(draft.activity.title) · \(draft.activity.trackingSummary)" : "\(draft.activity.title) · \(draft.exercises.count) exercises · \(draft.totalSets) target sets")
                    .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Not saved yet", systemImage: "square.and.pencil")
                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                if hasDuplicateSavedName { duplicateNameNotice }
            }
            .padding(18).workoutOutline(radius: 20)
            .accessibilityIdentifier("workout-builder-review-summary")
            if draft.tracksDistance {
                WorkoutPlanFields(draft: $draft, sections: .structure)
            } else {
                HStack(spacing: 10) {
                    Text("Exercises").font(.community(.headline))
                    Spacer()
                    if draft.exercises.count > 1 {
                        Button { reordering = true } label: {
                            Label("Reorder", systemImage: "arrow.up.arrow.down")
                                .font(.community(.caption, weight: .bold))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 30)
                                .background(phase.cardBorder.opacity(0.5), in: Capsule())
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    WeightUnitToggle(compact: true)
                }
                VStack(spacing: 10) {
                    ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { index, exercise in
                        reviewCard(exercise, index: index)
                    }
                }
                .animation(.snappy(duration: 0.22), value: draft.exercises.map(\.id))
                .sensoryFeedback(.selection, trigger: draft.exercises.map(\.id))
                if let removed {
                    Button("Undo removing \(removed.exercise.displayName)") {
                        draft.exercises.insert(removed.exercise, at: min(removed.index, draft.exercises.count))
                        self.removed = nil
                    }.font(.community(.caption))
                }
                Button { stage = .exercises } label: { Label("Add more exercises", systemImage: "plus").frame(minHeight: 44) }
                    .foregroundStyle(phase.accent)
                DisclosureGroup("Optional cardio finisher") {
                    Picker("Machine", selection: $draft.cardioMachine) {
                        Text("None").tag(Optional<CardioMachine>.none)
                        ForEach(CardioMachine.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    if draft.cardioMachine != nil {
                        Stepper("Target: \(draft.cardioTargetMinutes ?? 10) minutes", value: Binding(
                            get: { draft.cardioTargetMinutes ?? 10 }, set: { draft.cardioTargetMinutes = $0 }), in: 1...180)
                    }
                }.font(.community(.subheadline))
            }
        }
    }

    /// One exercise of the plan, compact enough that a whole workout fits on
    /// a screen or two, with what matters in reach: sets and their kinds, the
    /// rest, and optional targets. Reordering is the Reorder button's list,
    /// so no card carries a pair of arrows any more.
    private func reviewCard(_ exercise: Exercise, index: Int) -> some View {
        let binding = exerciseBinding(exercise.id)
        let supersetColor = exercise.supersetGroup.map { SupersetPalette.color(for: $0) }
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%02d", index + 1))
                        .font(.community(.caption, weight: .bold).monospacedDigit())
                        .foregroundStyle(phase.accent)
                    Text(exercise.displayName)
                        .font(.community(.subheadline, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let supersetColor {
                        Text("SUPERSET").font(.community(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(supersetColor)
                    }
                    Spacer(minLength: 0)
                    cardMenu(exercise, index: index)
                }
                setChips(binding)
                HStack(spacing: 8) {
                    RestDurationMenu(
                        selection: exercise.restSeconds,
                        defaultSeconds: store.preferences.defaultRestSeconds
                    ) { binding.wrappedValue.restSeconds = $0 } label: {
                        RestChip(seconds: exercise.restSeconds, defaultSeconds: store.preferences.defaultRestSeconds, phase: phase)
                    }
                    Spacer(minLength: 0)
                    targetField("Reps", value: Binding(
                        get: { binding.wrappedValue.targetReps.map(String.init) ?? "" },
                        set: { binding.wrappedValue.targetReps = Int($0.filter(\.isNumber).prefix(4)) }
                    ), keyboard: .numberPad, width: 46)
                    targetField(LocalizedStringKey(store.preferences.weightUnit.label), value: Binding(
                        get: { binding.wrappedValue.targetWeightKilograms.map { store.preferences.weightUnit.display(kilograms: $0) } ?? "" },
                        set: { value in
                            let trimmed = value.trimmingCharacters(in: .whitespaces)
                            binding.wrappedValue.targetWeightKilograms = trimmed.isEmpty
                                ? nil : store.preferences.weightUnit.kilograms(display: trimmed)
                        }
                    ), keyboard: .decimalPad, width: 58)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(phase.surfaceStart, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            if let supersetColor {
                Capsule().fill(supersetColor).frame(width: 3).padding(.vertical, 10)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(phase.cardBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(index + 1). \(exercise.displayName), \(exercise.sets) sets")
        .accessibilityAction(named: "Move up") { moveExercise(exercise.id, by: -1) }
        .accessibilityAction(named: "Move down") { moveExercise(exercise.id, by: 1) }
    }

    private func cardMenu(_ exercise: Exercise, index: Int) -> some View {
        Menu {
            if index < draft.exercises.count - 1 {
                Button {
                    supersetWithNext(exercise.id)
                } label: { Label("Superset with next exercise", systemImage: "link") }
            }
            if exercise.supersetGroup != nil {
                Button {
                    exerciseBinding(exercise.id).wrappedValue.supersetGroup = nil
                    draft.exercises = Self.withoutLoneSupersets(draft.exercises)
                } label: { Label("Remove from superset", systemImage: "link.badge.plus") }
            }
            Divider()
            Button(role: .destructive) {
                guard let i = draft.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
                removed = (draft.exercises.remove(at: i), i)
                draft.exercises = Self.withoutLoneSupersets(draft.exercises)
            } label: { Label("Remove", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.community(.subheadline, weight: .bold))
                .foregroundStyle(phase.secondaryText)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Options for \(exercise.displayName)")
    }

    /// The planned sets as small badges, one per set, each opening a menu of
    /// kinds; with the count's minus and plus beside them.
    private func setChips(_ exercise: Binding<Exercise>) -> some View {
        let types = exercise.wrappedValue.plannedSetTypes
        let labels = WorkoutSetPolicy.labels(for: types)
        return HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(types.enumerated()), id: \.offset) { index, type in
                        Menu {
                            ForEach(WorkoutSetType.allCases) { kind in
                                Button { exercise.wrappedValue.setType(kind, at: index) } label: {
                                    Label(kind.title, systemImage: kind == type ? "checkmark" : kind.symbol)
                                }
                            }
                        } label: {
                            SetTypeBadge(type: type, label: labels[index])
                                .scaleEffect(0.9)
                                .frame(minWidth: 32, minHeight: 36)
                        }
                        .accessibilityLabel("Set \(index + 1): \(type.title)")
                    }
                }
            }
            Text("\(types.count) sets")
                .font(.community(.caption, weight: .semibold).monospacedDigit())
                .foregroundStyle(phase.secondaryText)
                .fixedSize()
            Stepper("", value: Binding(
                get: { max(exercise.wrappedValue.sets, 1) },
                set: { count in
                    exercise.wrappedValue.sets = count
                    exercise.wrappedValue.setTypes = WorkoutStructureDiff.storedSetTypes(
                        Array(exercise.wrappedValue.plannedSetTypes.prefix(count))
                    )
                }
            ), in: 1...50)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("\(exercise.wrappedValue.name) target sets")
        }
    }

    private func targetField(_ title: LocalizedStringKey, value: Binding<String>, keyboard: UIKeyboardType, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            TextField("—", text: value)
                .keyboardType(keyboard)
                .multilineTextAlignment(.center)
                .font(.community(.subheadline, weight: .bold).monospacedDigit())
                .frame(width: width, height: 32)
                .background(phase.cardBorder.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            Text(title).font(.community(.caption2, weight: .semibold)).foregroundStyle(phase.secondaryText)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Target \(Text(title))"))
    }

    private func exerciseBinding(_ id: Exercise.ID) -> Binding<Exercise> {
        Binding(
            get: { draft.exercises.first { $0.id == id } ?? Exercise(name: "") },
            set: { updated in
                guard let i = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
                draft.exercises[i] = updated
            }
        )
    }

    private func supersetWithNext(_ id: Exercise.ID) {
        guard let i = draft.exercises.firstIndex(where: { $0.id == id }), draft.exercises.indices.contains(i + 1) else { return }
        let group = draft.exercises[i].supersetGroup
            ?? draft.exercises[i + 1].supersetGroup
            ?? ((draft.exercises.compactMap(\.supersetGroup).max() ?? 0) + 1)
        draft.exercises[i].supersetGroup = group
        draft.exercises[i + 1].supersetGroup = group
    }

    /// A superset left with one exercise in it is just an exercise.
    private static func withoutLoneSupersets(_ exercises: [Exercise]) -> [Exercise] {
        let counts = Dictionary(grouping: exercises.compactMap(\.supersetGroup), by: { $0 }).mapValues(\.count)
        return exercises.map { exercise in
            var exercise = exercise
            if let group = exercise.supersetGroup, counts[group, default: 0] < 2 { exercise.supersetGroup = nil }
            return exercise
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stage != .identity && isStrength {
                Text("\(draft.exercises.count) exercises · \(draft.totalSets) target sets")
                    .font(.community(.subheadline, weight: .bold))
                    .accessibilityIdentifier("workout-builder-draft-count")
            }
            Button {
                switch stage {
                case .identity: stage = isStrength ? .exercises : logsActivity ? .details : .review
                case .exercises: stage = .review
                case .details: detailsMode == .log ? saveLog() : savePlan()
                case .review: savePlan()
                }
            } label: {
                HStack {
                    if isSaving { ProgressView().tint(phase.onPrimaryAction) }
                    Text(footerTitle)
                    Spacer()
                    if !isSaving { Image(systemName: stage == .review || stage == .details ? "checkmark" : "arrow.forward") }
                }.frame(maxWidth: .infinity)
            }.buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
                .disabled(isSaving || (stage == .exercises && draft.exercises.isEmpty) || ((stage == .review || (stage == .details && detailsMode == .plan)) && !canSave))
                .accessibilityIdentifier("workout-builder-primary")
            if let logProblem, stage == .details, detailsMode == .log {
                Text(logProblem.message).font(.community(.caption)).foregroundStyle(RepbaseDesign.danger)
            } else {
                Text(footerNote)
                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
            }
            if stage == .review && isStrength && draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Give your workout a name above to save it.").font(.community(.caption)).foregroundStyle(phase.accent)
            }
        }.padding(.horizontal, 20).padding(.vertical, 12).background(phase.canvasStart)
    }

    private var footerTitle: LocalizedStringKey {
        if isSaving { return stage == .details && detailsMode == .log ? "Saving activity…" : "Saving workout…" }
        switch stage {
        case .identity: return isStrength ? "Add exercises" : logsActivity ? "Add details" : "Review workout"
        case .exercises: return "Review \(draft.exercises.count) exercises"
        case .details: return detailsMode == .log ? "Save to history" : "Save workout"
        case .review: return "Save workout"
        }
    }

    private var footerNote: LocalizedStringKey {
        switch stage {
        case .identity:
            return isStrength ? "Next: choose exercises, then target sets." : logsActivity ? "Next: how long it took and how hard it felt." : "Next: review your session before saving."
        case .exercises: return "Next: choose sets and arrange your workout."
        case .details:
            return detailsMode == .log ? "Saved to this day’s history as \(log.displayName)." : "Start your session when you’re ready to move."
        case .review:
            return isStrength ? "Plan now. Log your weight and reps when you train." : "Start your session when you’re ready to move."
        }
    }

    /// The plan, named after its activity when nobody named it.
    private func savePlan() {
        if !isStrength {
            if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.name = draft.activity.title
            }
            // Exercises picked before switching to tennis stay in the draft,
            // in case of switching back, but a match is not saved with them.
            draft.exercises = []
            draft.cardioMachine = nil
        }
        onSave()
    }

    private func saveLog() {
        guard let logging else { return }
        log.name = draft.name
        switch log.validated() {
        case .success(let entry):
            logProblem = nil
            logging.onLog(entry)
        case .failure(let problem):
            logProblem = problem
        }
    }

    /// The second step of anything that is not sets: log it, or plan it.
    private var details: some View {
        VStack(alignment: .leading, spacing: 22) {
            Picker("What do you want to do?", selection: $detailsMode) {
                Text("Log a finished session").tag(DetailsMode.log)
                Text("Plan for later").tag(DetailsMode.plan)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("activity-details-mode")

            HStack(spacing: 12) {
                Image(systemName: draft.activity.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(phase.accent)
                    .frame(width: 44, height: 44)
                    .background(phase.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.displayName).font(.community(.headline))
                    Text(draft.activity.title).font(.community(.caption)).foregroundStyle(phase.secondaryText)
                }
                Spacer(minLength: 0)
            }

            if detailsMode == .log {
                ActivityLogFields(draft: $log, phase: phase, finishedRange: logging?.finishedRange ?? Date.distantPast...Date())
                    .onChange(of: log) { logProblem = nil }
            } else {
                review
            }
        }
    }

    private var canSave: Bool {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // The matching library row may be this draft's committed write whose
        // read-back failed. Warn, but keep its idempotent Retry available.
        return (!name.isEmpty || !isStrength) && name.count <= 150 && (draft.tracksDistance || !draft.exercises.isEmpty)
            && draft.exercises.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 150 && $0.sets >= 1 }
    }

    private var hasDuplicateSavedName: Bool {
        guard draft.serverID == nil else { return false }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && suggestions.contains { $0.name == name }
    }

    private var duplicateNameNotice: some View {
        Label("This name is already in your library. Choose a different name for a new workout. If you’re retrying a save, keep the name so we can confirm it.", systemImage: "info.circle")
            .font(.community(.caption)).foregroundStyle(phase.accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func eyebrow(_ label: LocalizedStringKey) -> some View {
        Text(label).font(.community(.caption2, weight: .bold)).foregroundStyle(phase.secondaryText)
    }

    /// For VoiceOver, which cannot drag: the same move one place at a time.
    private func moveExercise(_ id: UUID, by offset: Int) {
        guard let i = draft.exercises.firstIndex(where: { $0.id == id }), draft.exercises.indices.contains(i + offset) else { return }
        draft.exercises.swapAt(i, i + offset)
    }

    /// Catalog identity wins over spelling: an exercise with a server id is
    /// matched by it, and one from the library, which has none until the
    /// workout is saved, by name.
    private func toggle(_ option: ExerciseOption) {
        if let i = draft.exercises.firstIndex(where: { option.matches(serverID: $0.serverID, name: $0.name) }) {
            draft.exercises.remove(at: i)
        } else {
            draft.exercises.append(Exercise(
                serverID: option.serverID,
                serverName: option.serverID == nil ? nil : option.name,
                name: option.name,
                sets: 3
            ))
        }
    }

    /// A name with no exercise behind it. The picker only offers this when no
    /// exercise of that name exists, so one already in the catalogue is
    /// chosen rather than created a second time.
    private func addCustomExercise(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 150 else { return }
        guard !draft.exercises.contains(where: { WorkoutSummary.matches($0.name, name) }) else { return }
        if let existing = store.catalog.existing(named: name) {
            draft.exercises.append(Exercise(serverID: existing.id, serverName: existing.name, name: existing.name, sets: 3))
        } else {
            draft.exercises.append(Exercise(name: name, sets: 3))
        }
    }

    private var reuseSheet: some View {
        NavigationStack {
            List(suggestions) { saved in
                Button {
                    draft.name = saved.name
                    draft.activity = saved.activity
                    // The whole plan is copied, set kinds and rests included,
                    // but never the saved rows themselves: this is a new
                    // workout, and it gets rows of its own.
                    draft.exercises = saved.exercises.map {
                        Exercise(
                            serverID: $0.serverID, serverName: $0.serverName ?? $0.name, name: $0.name,
                            sets: max($0.sets, 1), setTypes: $0.setTypes, restSeconds: $0.restSeconds,
                            supersetGroup: $0.supersetGroup, targetReps: $0.targetReps,
                            targetWeightKilograms: $0.targetWeightKilograms
                        )
                    }
                    reusing = false
                    stage = .review
                } label: { Label(saved.name, systemImage: saved.activity.symbol) }
            }
            .navigationTitle("Your saved workouts")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { reusing = false } } }
        }
    }
}

extension View {
    func workoutOutline(selected: Bool = false, radius: CGFloat = 14) -> some View {
        background(WorkoutVisualPhase.prepare.surfaceStart, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(selected ? WorkoutVisualPhase.prepare.accent : WorkoutVisualPhase.prepare.cardBorder, lineWidth: selected ? 1.5 : 1) }
    }
}

/// The plan's exercises as one compact row each, to drag into a new order.
///
/// The system list's own drag: rows lift, the others part to make room, and
/// a drop anywhere ends it. A drag done with SwiftUI's general drag and drop
/// across the review cards had no way to tell when it was abandoned, which
/// could leave a card drawn mid-drag. Sets, kinds, rests and supersets move
/// with their exercise.
private struct DraftReorderSheet: View {
    @Binding var exercises: [Exercise]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(exercises) { exercise in
                        HStack(spacing: 12) {
                            if let group = exercise.supersetGroup {
                                Capsule().fill(SupersetPalette.color(for: group)).frame(width: 4, height: 28)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.displayName).font(.community(.subheadline, weight: .semibold))
                                Text("\(exercise.sets) sets")
                                    .font(.community(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Drag to change the order. Sets, rests and supersets move with each exercise.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .sensoryFeedback(.selection, trigger: exercises.map(\.id))
            .navigationTitle("Reorder exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
