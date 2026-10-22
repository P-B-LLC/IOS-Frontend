import SwiftUI

/// The same draft travels through every step; navigation never writes a plan.
struct GuidedWorkoutBuilder: View {
    enum Stage { case identity, exercises, review }
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
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(stage == .exercises ? "LIFTING · YOUR WORKOUT" : "YOUR WORKOUT, YOUR WAY")
                .font(.community(.caption2, weight: .bold)).foregroundStyle(phase.accent)
            Text(stage == .identity ? "Make room for\nyour next win." : stage == .exercises ? "Start with a few\ngood moves." : "Your workout.\nYour way.")
                .font(.community(.largeTitle, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text(stage == .identity ? "Start small. You can build as you go." : stage == .exercises ? "Pick your exercises. Set the details next." : "Choose your sets. Make the order work for you.")
                .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                eyebrow("1  GIVE IT A NAME")
                TextField("e.g. Push day", text: $draft.name)
                    .font(.community(.headline)).textInputAutocapitalization(.words)
                    .padding(16).workoutOutline()
                Text("Make it yours—or name it before saving.")
                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
            }
            VStack(alignment: .leading, spacing: 12) {
                eyebrow("2  HOW ARE YOU MOVING?")
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
                Text("Already have a favorite?").font(.community(.headline))
                Button { reusing = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Use a previous workout").font(.community(.subheadline, weight: .bold))
                            Text("Keep its exercises and progress history").font(.community(.caption2)).foregroundStyle(phase.secondaryText)
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
                    let selected = draft.exercises.contains { $0.serverID == choice.id || WorkoutSummary.matches($0.name, choice.name) }
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
                    }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            if !draft.exercises.isEmpty {
                Text("Selected: " + draft.exercises.map(\.name).joined(separator: ", "))
                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
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

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Workout name", text: $draft.name).font(.community(.title2, weight: .bold))
                .textInputAutocapitalization(.words).accessibilityLabel("Workout name")
            Text("\(draft.type.title) · \(draft.exercises.count) exercises · \(draft.totalSets) target sets")
                .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
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
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Target sets").font(.community(.subheadline, weight: .bold))
                    Text("Weight & reps later").font(.community(.caption2)).foregroundStyle(phase.secondaryText)
                }
                Spacer(minLength: 8)
                Stepper(value: Binding(get: { max(exercise.sets, 1) }, set: { count in
                    if let i = draft.exercises.firstIndex(where: { $0.id == exercise.id }) { draft.exercises[i].sets = count }
                }), in: 1...999) { Text("\(max(exercise.sets, 1))").font(.community(.title2, weight: .bold)).monospacedDigit() }
                    .fixedSize().accessibilityLabel("\(exercise.name) target sets")
            }
            HStack(spacing: 8) {
                Text("Move").font(.community(.caption)).foregroundStyle(phase.secondaryText)
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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stage != .identity { Text("\(draft.exercises.count) exercises · \(draft.totalSets) target sets").font(.community(.subheadline, weight: .bold)) }
            Button {
                switch stage {
                case .identity: stage = draft.type == .lifting ? .exercises : .review
                case .exercises: stage = .review
                case .review: onSave()
                }
            } label: {
                HStack {
                    Text(stage == .identity ? (draft.type == .lifting ? "Add exercises" : "Review workout") : stage == .exercises ? "Review \(draft.exercises.count) exercises" : "Save workout")
                    Spacer()
                    Image(systemName: stage == .review ? "checkmark" : "arrow.right")
                }.frame(maxWidth: .infinity)
            }.buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
                .disabled(isSaving || (stage == .exercises && draft.exercises.isEmpty) || (stage == .review && !canSave))
            Text(stage == .identity ? (draft.type == .lifting ? "Next: choose exercises, then target sets." : "Next: review your session before saving.") : stage == .exercises ? "Next: choose sets and arrange your workout." : draft.type == .lifting ? "Plan now. Log your weight and reps when you train." : "Start your session when you’re ready to move.")
                .font(.community(.caption)).foregroundStyle(phase.secondaryText)
            if stage == .review && draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Give your workout a name above to save it.").font(.community(.caption)).foregroundStyle(phase.accent)
            }
        }.padding(.horizontal, 24).padding(.vertical, 12).background(phase.canvasStart)
    }

    private var canSave: Bool {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 150 && (draft.type.tracksDistance || !draft.exercises.isEmpty)
            && draft.exercises.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 150 && $0.sets >= 1 }
    }

    private func eyebrow(_ label: String) -> some View {
        Text(label).font(.community(.caption2, weight: .bold)).foregroundStyle(phase.secondaryText)
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let i = draft.exercises.firstIndex(where: { $0.id == id }), draft.exercises.indices.contains(i + offset) else { return }
        draft.exercises.swapAt(i, i + offset)
    }

    private func toggle(_ choice: WorkoutExerciseChoice) {
        if let i = draft.exercises.firstIndex(where: { $0.serverID == choice.id || WorkoutSummary.matches($0.name, choice.name) }) { draft.exercises.remove(at: i) }
        else { draft.exercises.append(Exercise(serverID: choice.id, serverName: choice.name, name: choice.name, sets: 3)) }
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
            .navigationTitle("Previous workouts")
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
