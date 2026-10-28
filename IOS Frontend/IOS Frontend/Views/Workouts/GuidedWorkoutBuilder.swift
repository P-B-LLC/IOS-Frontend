import SwiftUI

/// The same draft travels through every step; navigation never writes a plan.
struct GuidedWorkoutBuilder: View {
    enum Stage: Hashable { case identity, exercises, review }
    @Binding var draft: Workout
    let suggestions: [WorkoutSummary]
    let startsAtReview: Bool
    let isSaving: Bool
    let onSave: () -> Void
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var stage: Stage = .identity
    @State private var initialized = false
    @State private var choices: [WorkoutExerciseChoice] = []
    @State private var nextPage: Int? = 1
    @State private var loading = false
    @State private var loadError: String?
    @State private var query = ""
    @State private var muscle = "All"
    @State private var reusing = false
    @State private var custom = false
    @State private var customName = ""
    @State private var removed: (exercise: Exercise, index: Int)?
    private let phase = WorkoutVisualPhase.prepare

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                intro
                switch stage {
                case .identity: identity
                case .exercises: exercisePicker
                case .review: review
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        // Each step starts at its heading, even after scrolling a long catalog.
        .id(stage)
        .safeAreaInset(edge: .bottom) { footer }
        .navigationTitle(stage == .identity ? "New workout" : stage == .exercises ? "Add exercises" : "Review workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(stage == .identity ? "Cancel" : "Back") {
                    switch stage {
                    case .identity: dismiss()
                    case .exercises: stage = .identity
                    case .review: stage = draft.type == .lifting ? .exercises : .identity
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
        }
        .task(id: stage == .exercises && store.isConnected) {
            if stage == .exercises, choices.isEmpty, store.isConnected { await loadMore() }
        }
        .sheet(isPresented: $reusing) { reuseSheet }
        .onChange(of: draft.exercises) { _, _ in
            // Recovery can arrive after onAppear. Keep the visible minimum and
            // the value that will actually be saved consistent.
            for i in draft.exercises.indices where draft.exercises[i].sets < 1 { draft.exercises[i].sets = 1 }
        }
        .alert("Create an exercise", isPresented: $custom) {
            TextField("Exercise name", text: $customName)
            Button("Add") { addCustomExercise() }
                .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || customName.count > 150)
            Button("Cancel", role: .cancel) { customName = "" }
        } message: { Text("Choose a name. You’ll set target sets on the next screen.") }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                progressStep("Name", number: 1, step: .identity)
                if draft.type == .lifting {
                    progressStep("Exercises", number: 2, step: .exercises)
                }
                progressStep("Review", number: draft.type == .lifting ? 3 : 2, step: .review)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(stageNumber) of \(draft.type == .lifting ? 3 : 2): \(stage == .identity ? "Name" : stage == .exercises ? "Exercises" : "Review")")

            Text(stage == .identity ? "Name your workout. Add only what you want to train." : stage == .exercises ? "Every exercise you add appears in your workout below." : draft.type.tracksDistance ? "Review your workout, then save it when you’re ready." : "Check the order and target sets. These are the exercises you’ll train.")
                .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stageNumber: Int {
        switch stage {
        case .identity: 1
        case .exercises: 2
        case .review: draft.type == .lifting ? 3 : 2
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
                TextField("e.g. Push day", text: $draft.name)
                    .font(.community(.headline)).textInputAutocapitalization(.words)
                    .padding(16).workoutOutline()
                Text("Make it yours—or name it before saving.")
                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                if hasDuplicateSavedName { duplicateNameNotice }
            }
            VStack(alignment: .leading, spacing: 12) {
                eyebrow("HOW ARE YOU MOVING?")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(WorkoutType.allCases) { type in
                        Button { draft.type = type } label: {
                            HStack(spacing: 10) {
                                Image(systemName: type.builderSymbol).font(.system(size: 20))
                                    .foregroundStyle(draft.type == type ? phase.accent : phase.secondaryText)
                                Text(type == .biking ? "Cycling" : type.title).font(.community(.subheadline, weight: .bold))
                                Spacer(minLength: 0)
                            }
                            .padding(14).frame(maxWidth: .infinity, minHeight: 72)
                            .workoutOutline(selected: draft.type == type)
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(draft.type == type ? [.isSelected] : [])
                    }
                }
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
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(14).workoutOutline()
                }.buttonStyle(.plain).disabled(suggestions.isEmpty)
                if suggestions.isEmpty { Text("Your saved workouts will appear here.").font(.community(.caption)).foregroundStyle(phase.secondaryText) }
            }
        }
    }

    private var available: [WorkoutExerciseChoice] {
        var seen: Set<Int> = []
        return choices.filter { seen.insert($0.id).inserted }
    }

    private var filtered: [WorkoutExerciseChoice] {
        available.filter {
            (muscle == "All" || $0.muscleGroup == muscle)
                && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
        }
    }

    private var exercisePicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            selectedExercises
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(phase.secondaryText)
                TextField("Search loaded exercises", text: $query).textInputAutocapitalization(.never)
            }.padding(14).workoutOutline()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["All"] + Set(available.map(\.muscleGroup).filter { !$0.isEmpty && $0 != "All" }).sorted(), id: \.self) { group in
                        Button(group) { muscle = group }
                            .font(.community(.caption, weight: .semibold)).padding(.horizontal, 14).frame(minHeight: 44)
                            .foregroundStyle(muscle == group ? phase.onPrimaryAction : phase.primaryText)
                            .background(muscle == group ? phase.primaryActionSurface : phase.surfaceStart, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityAddTraits(muscle == group ? [.isSelected] : [])
                    }
                }
            }
            HStack {
                Text("Explore exercises").font(.community(.headline))
                Spacer()
                Text("\(draft.exercises.count) selected").font(.community(.caption, weight: .bold)).foregroundStyle(phase.accent)
            }
            LazyVStack(spacing: 10) {
                ForEach(filtered) { choice in
                    let selected = draft.exercises.contains { matches($0, choice: choice) }
                    Button { toggle(choice) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(choice.name).font(.community(.headline))
                                Text((choice.muscleGroup.isEmpty ? "Exercise" : choice.muscleGroup) + (selected ? " · Selected" : ""))
                                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 24)).foregroundStyle(selected ? phase.accent : phase.secondaryText)
                        }.padding(14).frame(maxWidth: .infinity, minHeight: 76).workoutOutline(selected: selected)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(selected ? "Remove" : "Add") \(choice.name)")
                        .accessibilityValue(selected ? "Added to your workout" : "Not added")
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            if loading { ProgressView("Loading exercises…") }
            if let loadError {
                Text(loadError).font(.community(.caption)).foregroundStyle(.red)
                Button("Retry") { Task { await loadMore() } }
            } else if nextPage != nil {
                Button("Load more exercises") { Task { await loadMore() } }.disabled(loading || !store.isConnected)
            }
            if !loading && filtered.isEmpty {
                Text(nextPage == nil ? "No matching exercises. Create one below." : "No matches in the loaded exercises. Load more or create your own.")
                    .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
            }
            Button { customName = query; custom = true } label: {
                Label("Create an exercise", systemImage: "plus").frame(minHeight: 44)
            }.foregroundStyle(phase.accent)
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
                        Text(exercise.name).font(.community(.subheadline, weight: .semibold))
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
                        .accessibilityLabel("Remove \(exercise.name) from your workout")
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
                Text(draft.type.tracksDistance ? "\(draft.type.title) · distance and time recorded during your session" : "\(draft.type.title) · \(draft.exercises.count) exercises · \(draft.totalSets) target sets")
                    .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Not saved yet", systemImage: "square.and.pencil")
                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                if hasDuplicateSavedName { duplicateNameNotice }
            }
            .padding(18).workoutOutline(radius: 20)
            .accessibilityIdentifier("workout-builder-review-summary")
            if draft.type.tracksDistance {
                WorkoutPlanFields(draft: $draft, sections: .structure)
            } else {
                ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { index, exercise in
                    reviewCard(exercise, index: index)
                }
                if let removed {
                    Button("Undo removing \(removed.exercise.name)") {
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

    private func reviewCard(_ exercise: Exercise, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%02d", index + 1)).font(.community(.caption, weight: .bold)).foregroundStyle(phase.accent)
                Text(exercise.name).font(.community(.headline))
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    targetSetsLabel
                    targetSetsStepper(for: exercise)
                }
            } else {
                HStack {
                    targetSetsLabel
                    Spacer(minLength: 8)
                    targetSetsStepper(for: exercise).fixedSize()
                }
            }
            HStack(spacing: 8) {
                Button { move(exercise.id, by: -1) } label: { Image(systemName: "arrow.up").frame(width: 44, height: 44) }
                    .buttonStyle(.bordered).disabled(index == 0).accessibilityLabel("Move \(exercise.name) up")
                Button { move(exercise.id, by: 1) } label: { Image(systemName: "arrow.down").frame(width: 44, height: 44) }
                    .buttonStyle(.bordered).disabled(index == draft.exercises.count - 1).accessibilityLabel("Move \(exercise.name) down")
                Spacer(minLength: 0)
                Button("Remove", systemImage: "xmark") {
                    guard let i = draft.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
                    removed = (draft.exercises.remove(at: i), i)
                }.font(.community(.caption)).frame(minHeight: 44)
            }
        }.padding(16).workoutOutline(radius: 20)
    }

    private var targetSetsLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Target sets").font(.community(.subheadline, weight: .bold))
            Text("Weight & reps later").font(.community(.caption2)).foregroundStyle(phase.secondaryText)
        }
    }

    private func targetSetsStepper(for exercise: Exercise) -> some View {
        Stepper(value: Binding(get: { max(exercise.sets, 1) }, set: { count in
            if let i = draft.exercises.firstIndex(where: { $0.id == exercise.id }) { draft.exercises[i].sets = count }
        }), in: 1...999) {
            Text("\(max(exercise.sets, 1))").font(.community(.title2, weight: .bold)).monospacedDigit()
        }
        .frame(minHeight: 44)
        .accessibilityLabel("\(exercise.name) target sets")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stage != .identity && !draft.type.tracksDistance {
                Text("\(draft.exercises.count) exercises · \(draft.totalSets) target sets")
                    .font(.community(.subheadline, weight: .bold))
                    .accessibilityIdentifier("workout-builder-draft-count")
            }
            Button {
                switch stage {
                case .identity: stage = draft.type == .lifting ? .exercises : .review
                case .exercises: stage = .review
                case .review: onSave()
                }
            } label: {
                HStack {
                    if isSaving { ProgressView().tint(phase.onPrimaryAction) }
                    Text(isSaving ? "Saving workout…" : stage == .identity ? (draft.type == .lifting ? "Add exercises" : "Review workout") : stage == .exercises ? "Review \(draft.exercises.count) exercises" : "Save workout")
                    Spacer()
                    if !isSaving { Image(systemName: stage == .review ? "checkmark" : "arrow.right") }
                }.frame(maxWidth: .infinity)
            }.buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
                .disabled(isSaving || (stage == .exercises && draft.exercises.isEmpty) || (stage == .review && !canSave))
            Text(stage == .identity ? (draft.type == .lifting ? "Next: choose exercises, then target sets." : "Next: review your session before saving.") : stage == .exercises ? "Next: choose sets and arrange your workout." : draft.type == .lifting ? "Plan now. Log your weight and reps when you train." : "Start your session when you’re ready to move.")
                .font(.community(.caption)).foregroundStyle(phase.secondaryText)
            if stage == .review && draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Give your workout a name above to save it.").font(.community(.caption)).foregroundStyle(phase.accent)
            }
        }.padding(.horizontal, 20).padding(.vertical, 12).background(phase.canvasStart)
    }

    private var canSave: Bool {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // The matching library row may be this draft's committed write whose
        // read-back failed. Warn, but keep its idempotent Retry available.
        return !name.isEmpty && name.count <= 150 && (draft.type.tracksDistance || !draft.exercises.isEmpty)
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

    private func eyebrow(_ label: String) -> some View {
        Text(label).font(.community(.caption2, weight: .bold)).foregroundStyle(phase.secondaryText)
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let i = draft.exercises.firstIndex(where: { $0.id == id }), draft.exercises.indices.contains(i + offset) else { return }
        draft.exercises.swapAt(i, i + offset)
    }

    private func toggle(_ choice: WorkoutExerciseChoice) {
        if let i = draft.exercises.firstIndex(where: { matches($0, choice: choice) }) { draft.exercises.remove(at: i) }
        else { draft.exercises.append(Exercise(serverID: choice.id, serverName: choice.name, name: choice.name, sets: 3)) }
    }

    /// Catalog identity wins over spelling. Only an unsaved custom exercise
    /// may match a catalog choice by name before it has a server ID.
    private func matches(_ exercise: Exercise, choice: WorkoutExerciseChoice) -> Bool {
        if let serverID = exercise.serverID { return serverID == choice.id }
        return WorkoutSummary.matches(exercise.name, choice.name)
    }

    private func addCustomExercise() {
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 150 else { return }
        guard !draft.exercises.contains(where: { WorkoutSummary.matches($0.name, name) }) else { return }
        draft.exercises.append(Exercise(name: name, sets: 3))
        customName = ""
    }

    @MainActor private func loadMore() async {
        guard !loading, let page = nextPage else { return }
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            let result = try await store.exerciseChoices(page: page)
            try Task.checkCancellation()
            choices.append(contentsOf: result.items)
            nextPage = result.nextPage
        } catch is CancellationError { } catch { loadError = error.userFacingMessage ?? error.localizedDescription }
    }

    private var reuseSheet: some View {
        NavigationStack {
            List(suggestions) { saved in
                Button {
                    draft.name = saved.name
                    draft.type = saved.type
                    draft.exercises = saved.exercises.map {
                        Exercise(serverID: $0.serverID, serverName: $0.serverName ?? $0.name, name: $0.name, sets: max($0.sets, 1))
                    }
                    reusing = false
                    stage = .review
                } label: { Label(saved.name, systemImage: saved.type.builderSymbol) }
            }
            .navigationTitle("Your saved workouts")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { reusing = false } } }
        }
    }
}

extension WorkoutType {
    var builderSymbol: String {
        switch self {
        case .lifting: "dumbbell"
        case .running: "figure.run"
        case .biking: "bicycle"
        case .swimming: "figure.pool.swim"
        }
    }
}

extension View {
    func workoutOutline(selected: Bool = false, radius: CGFloat = 14) -> some View {
        background(WorkoutVisualPhase.prepare.surfaceStart, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(selected ? WorkoutVisualPhase.prepare.accent : WorkoutVisualPhase.prepare.cardBorder, lineWidth: selected ? 1.5 : 1) }
    }
}
