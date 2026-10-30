//
//  ExerciseCatalogPicker.swift
//  IOS Frontend
//
//  Explore and choose exercises. Used by the workout builder and by the
//  add-exercise sheet of a session in progress.
//

import SwiftUI

/// One exercise as the picker offers it: from the library, from the server,
/// or both at once.
///
/// A library exercise has no server id until a workout using it is saved;
/// the save looks its name up, so it becomes the server's shared row where
/// the server has the library, and the account's own exercise where it does
/// not. Picking it twice never makes two, because both paths match by name.
struct ExerciseOption: Identifiable, Hashable {
    let name: String
    let serverID: Int?
    let library: LibraryExercise?
    /// Created by this account rather than shipped with the app.
    let isCustom: Bool
    let muscleGroup: String

    var id: String { serverID.map { "server-\($0)" } ?? "library-\(library?.slug ?? name)" }

    var detail: String {
        if let library, !library.detailLine.isEmpty { return library.detailLine }
        if !muscleGroup.isEmpty { return MuscleRegion(serverMuscleGroup: muscleGroup)?.title ?? muscleGroup }
        return isCustom
            ? String(localized: "Your exercise", bundle: .app, locale: .app)
            : String(localized: "Exercise", bundle: .app, locale: .app)
    }

    /// Whether a planned or logged exercise is this one: by id when both
    /// have one, else by name, the way the server matches names.
    func matches(serverID other: Int?, name otherName: String) -> Bool {
        if let serverID, let other { return serverID == other }
        return WorkoutSummary.matches(name, otherName)
    }
}

/// The exercise library to search and filter, with the account's own
/// exercises first, and a way to create one that is missing.
///
/// Exercises, not workouts: everything here is one movement, and a workout is
/// what is built out of them. An exercise is a single record however many
/// workouts it appears in, which is why choosing one here never makes a copy.
///
/// The library ships with the app, so searching and filtering a thousand
/// exercises works offline and at once. The server's catalogue is still read:
/// it holds the account's own exercises, and anything shared that this build
/// does not know yet.
struct ExerciseCatalogPicker: View {
    let isSelected: (ExerciseOption) -> Bool
    let onToggle: (ExerciseOption) -> Void
    /// A name with no exercise behind it yet. Creating it is the caller's call:
    /// the builder adds it to the draft, a session adds it to the workout.
    let onCreate: (String) -> Void
    var phase: WorkoutVisualPhase = .prepare
    /// Names chosen but not yet saved, so a custom exercise shows as chosen
    /// before the server has given it an id.
    var pendingCustomNames: [String] = []

    @Environment(WorkoutStore.self) private var store
    @State private var query = ""
    @State private var filter = ExerciseFilter()
    @State private var showingFilters = false
    @State private var shownLimit = Self.pageSize
    @State private var detail: LibraryExercise?

    private static let pageSize = 40
    private var library: ExerciseLibrary? { ExerciseLibrary.shared }
    private var catalog: ExerciseCatalog { store.catalog }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The account's own exercises that match, each with its library entry
    /// when its name is one the library knows.
    private var ownResults: [ExerciseOption] {
        let words = ExerciseSearch.words(trimmedQuery)
        return catalog.mine.compactMap { choice -> ExerciseOption? in
            let entry = library?.exercise(named: choice.name)
            let option = ExerciseOption(name: choice.name, serverID: choice.id, library: entry, isCustom: true, muscleGroup: choice.muscleGroup)
            if let entry {
                guard filter.matches(entry) else { return nil }
            } else {
                guard filter.refinementCount == 0 else { return nil }
                if let region = filter.region, MuscleRegion(serverMuscleGroup: choice.muscleGroup) != region { return nil }
            }
            let haystack = ExerciseSearch.folded(([choice.name] + (entry?.aliases ?? [])).joined(separator: " "))
            return words.allSatisfy(haystack.contains) ? option : nil
        }
    }

    /// Library matches, without the ones already listed as the account's own.
    private var libraryResults: [ExerciseOption] {
        guard let library else { return [] }
        let own = Set(catalog.mine.compactMap { library.exercise(named: $0.name)?.slug })
        // A shared row counts for the entry its name or an alias names, so a
        // pick reuses an exercise from before the library and its history.
        // A row with the entry's own name wins over an alias.
        var shared: [String: Int] = [:]
        for choice in catalog.items + catalog.searchResults where !choice.isCustom {
            guard let entry = library.exercise(named: choice.name) else { continue }
            if shared[entry.slug] == nil || ExerciseSearch.folded(choice.name) == ExerciseSearch.folded(entry.name) {
                shared[entry.slug] = choice.id
            }
        }
        return library.search(trimmedQuery, filter: filter)
            .filter { !own.contains($0.slug) }
            .map { entry in
                ExerciseOption(
                    name: entry.name,
                    serverID: shared[entry.slug],
                    library: entry,
                    isCustom: false,
                    muscleGroup: entry.region?.serverName ?? ""
                )
            }
    }

    /// Shared exercises on the server that this build's library does not
    /// have -- added since, or by hand. Only when no library-only filter is on.
    private var serverOnlyResults: [ExerciseOption] {
        guard filter.refinementCount == 0 else { return [] }
        return catalog.filtered(query: trimmedQuery, muscle: nil)
            .filter { !$0.isCustom && library?.exercise(named: $0.name) == nil }
            .filter { choice in filter.region.map { MuscleRegion(serverMuscleGroup: choice.muscleGroup) == $0 } ?? true }
            .map { ExerciseOption(name: $0.name, serverID: $0.id, library: nil, isCustom: false, muscleGroup: $0.muscleGroup) }
    }

    /// Offered only when nothing by that name -- or alias -- exists. A name
    /// already in use picks the existing exercise instead of creating a
    /// second one.
    private var creatableName: String? {
        let name = trimmedQuery
        guard !name.isEmpty, name.count <= 150,
              catalog.existing(named: name) == nil,
              library?.exercise(named: name) == nil,
              !pendingCustomNames.contains(where: { WorkoutSummary.matches($0, name) }) else { return nil }
        return name
    }

    var body: some View {
        let own = ownResults
        let fromLibrary = libraryResults
        let fromServer = serverOnlyResults
        VStack(alignment: .leading, spacing: 14) {
            searchField
            regionChips
            if let name = creatableName { createRow(name) }

            if !own.isEmpty {
                section(title: "Your exercises", items: own)
            }
            if !fromLibrary.isEmpty {
                section(
                    title: "Exercise library",
                    count: fromLibrary.count,
                    items: Array(fromLibrary.prefix(shownLimit))
                )
                if fromLibrary.count > shownLimit {
                    Button("Show more (\(fromLibrary.count - shownLimit))") { shownLimit += Self.pageSize }
                        .font(.community(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            if !fromServer.isEmpty {
                section(title: "More exercises", items: fromServer)
            }

            if catalog.isLoading || catalog.isSearching { ProgressView("Loading exercises…").frame(maxWidth: .infinity) }
            if let error = catalog.loadError, library == nil {
                Text(error).font(.community(.caption)).foregroundStyle(RepbaseDesign.danger)
                Button("Retry") { Task { await catalog.loadMore() } }
            }
            if own.isEmpty, fromLibrary.isEmpty, fromServer.isEmpty, !catalog.isLoading, !catalog.isSearching, creatableName == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text(trimmedQuery.isEmpty ? "No exercises match these filters." : "No matches. Try another name.")
                        .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
                    if !filter.isEmpty {
                        Button("Clear filters") { filter = ExerciseFilter() }
                            .font(.community(.subheadline, weight: .semibold))
                    }
                }
            }
        }
        .onChange(of: trimmedQuery) { shownLimit = Self.pageSize }
        .onChange(of: filter) { shownLimit = Self.pageSize }
        .task(id: store.isConnected) {
            if store.isConnected { await catalog.loadIfNeeded() }
        }
        .task(id: trimmedQuery) {
            // Debounced: a search per keystroke would be a request per letter.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await catalog.search(trimmedQuery)
        }
        .sheet(isPresented: $showingFilters) {
            ExerciseFilterSheet(filter: $filter, library: library)
        }
        .sheet(item: $detail) { exercise in
            ExerciseDetailSheet(
                exercise: exercise,
                library: library,
                isSelected: { isSelected(option(for: $0)) },
                onToggle: { onToggle(option(for: $0)) }
            )
        }
    }

    private func option(for exercise: LibraryExercise) -> ExerciseOption {
        let own = catalog.mine.first { library?.exercise(named: $0.name)?.slug == exercise.slug }
        let shared = (catalog.items + catalog.searchResults).first { !$0.isCustom && WorkoutSummary.matches($0.name, exercise.name) }
        return ExerciseOption(
            name: own?.name ?? exercise.name,
            serverID: own?.id ?? shared?.id,
            library: exercise,
            isCustom: own != nil,
            muscleGroup: exercise.region?.serverName ?? ""
        )
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(phase.secondaryText)
            TextField("Search or create an exercise", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("exercise-search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(phase.secondaryText)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 48).workoutOutline()
    }

    private var regionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { showingFilters = true } label: {
                    Label(
                        filter.refinementCount > 0 ? "Filters · \(filter.refinementCount)" : "Filters",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    .font(.community(.caption, weight: .semibold))
                    .padding(.horizontal, 12).frame(minHeight: 36)
                    .foregroundStyle(filter.refinementCount > 0 ? phase.onPrimaryAction : phase.primaryText)
                    .background(filter.refinementCount > 0 ? phase.accent : phase.surfaceStart, in: Capsule())
                    .overlay { Capsule().strokeBorder(phase.cardBorder, lineWidth: filter.refinementCount > 0 ? 0 : 1) }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("exercise-filters")
                chip(String(localized: "All", bundle: .app, locale: .app, comment: "Filter showing exercises for every muscle group"), selected: filter.region == nil) {
                    filter.region = nil
                }
                ForEach(MuscleRegion.allCases.filter { $0 != .neck }) { region in
                    chip(region.title, selected: filter.region == region) {
                        filter.region = filter.region == region ? nil : region
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.community(.caption, weight: .semibold))
                .padding(.horizontal, 14).frame(minHeight: 36)
                .foregroundStyle(selected ? phase.onPrimaryAction : phase.primaryText)
                .background(selected ? phase.primaryActionSurface : phase.surfaceStart, in: Capsule())
                .overlay { Capsule().strokeBorder(phase.cardBorder, lineWidth: selected ? 0 : 1) }
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func createRow(_ name: String) -> some View {
        Button { onCreate(name); query = "" } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(phase.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create “\(name)”").font(.community(.headline))
                    Text("A new exercise of your own").font(.community(.caption)).foregroundStyle(phase.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 60).workoutOutline()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func section(title: LocalizedStringKey, count: Int? = nil, items: [ExerciseOption]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.community(.headline))
                Spacer(minLength: 0)
                if let count {
                    Text("\(count)")
                        .font(.community(.caption, weight: .semibold).monospacedDigit())
                        .foregroundStyle(phase.secondaryText)
                }
            }
            LazyVStack(spacing: 8) {
                ForEach(items) { option in row(option) }
            }
        }
    }

    private func row(_ option: ExerciseOption) -> some View {
        let selected = isSelected(option)
        return HStack(spacing: 4) {
            Button { onToggle(option) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.name).font(.community(.subheadline, weight: .semibold))
                            .multilineTextAlignment(.leading)
                        Text(option.detail)
                            .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(selected ? phase.accent : phase.secondaryText)
                        .contentTransition(.symbolEffect(.replace))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selected ? "Remove \(option.name)" : "Add \(option.name)")
            .accessibilityValue(selected ? "Added to your workout" : "Not added")
            .accessibilityAddTraits(selected ? [.isSelected] : [])

            if let entry = option.library {
                Button { detail = entry } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(phase.secondaryText)
                        .frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How to do \(option.name)")
            }
        }
        .padding(.leading, 14).padding(.trailing, option.library == nil ? 14 : 4).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58)
        .workoutOutline(selected: selected)
    }
}

/// Equipment, movement, type and discipline: the filters beyond the muscle
/// chips, each "any" until chosen.
private struct ExerciseFilterSheet: View {
    @Binding var filter: ExerciseFilter
    let library: ExerciseLibrary?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Equipment") {
                    picker(selection: $filter.equipment, options: library?.equipmentInUse ?? ExerciseEquipment.allCases, title: \.title)
                }
                Section("Movement") {
                    picker(selection: $filter.pattern, options: library?.patternsInUse ?? MovementPattern.allCases, title: \.title)
                }
                Section("Type") {
                    picker(selection: $filter.type, options: library?.typesInUse ?? ExerciseType.allCases, title: \.title)
                }
                Section("Training style") {
                    picker(selection: $filter.discipline, options: library?.disciplinesInUse ?? ExerciseDiscipline.allCases, title: \.title)
                }
            }
            .navigationTitle("Filter exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        let region = filter.region
                        filter = ExerciseFilter()
                        filter.region = region
                    }
                    .disabled(filter.refinementCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func picker<Value: Hashable & Identifiable>(
        selection: Binding<Value?>,
        options: [Value],
        title: KeyPath<Value, String>
    ) -> some View {
        Picker(selection: selection) {
            Text("Any").tag(Value?.none)
            ForEach(options) { Text($0[keyPath: title]).tag(Value?.some($0)) }
        } label: {
            EmptyView()
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}

/// How to do an exercise: what it works, what it needs, the steps, and its
/// variations.
struct ExerciseDetailSheet: View {
    let exercise: LibraryExercise
    let library: ExerciseLibrary?
    let isSelected: (LibraryExercise) -> Bool
    let onToggle: (LibraryExercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var shown: LibraryExercise
    private let phase = WorkoutVisualPhase.prepare

    init(
        exercise: LibraryExercise,
        library: ExerciseLibrary?,
        isSelected: @escaping (LibraryExercise) -> Bool,
        onToggle: @escaping (LibraryExercise) -> Void
    ) {
        self.exercise = exercise
        self.library = library
        self.isSelected = isSelected
        self.onToggle = onToggle
        _shown = State(initialValue: exercise)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(shown.name).font(.community(.title2, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        if !shown.aliases.isEmpty {
                            Text("Also called \(shown.aliases.prefix(4).joined(separator: ", "))")
                                .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    WrappingLayout(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.community(.caption, weight: .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(phase.cardBorder.opacity(0.5), in: Capsule())
                        }
                    }

                    muscles

                    if !shown.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("How to do it").font(.community(.headline))
                            ForEach(Array(shown.instructions.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.community(.caption, weight: .bold).monospacedDigit())
                                        .foregroundStyle(phase.accent)
                                        .frame(width: 18, alignment: .leading)
                                    Text(step).font(.community(.subheadline))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    if shown.disciplineKinds.contains(.rehab) {
                        Label("Recovering from an injury? Follow your clinician’s advice on what to do and how much.", systemImage: "cross.case")
                            .font(.community(.caption))
                            .foregroundStyle(phase.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    let variations = library?.variations(of: shown) ?? []
                    if !variations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Variations").font(.community(.headline))
                            ForEach(variations.prefix(12)) { variation in
                                Button { withAnimation { shown = variation } } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(variation.name).font(.community(.subheadline, weight: .semibold))
                                            Text(variation.detailLine).font(.community(.caption)).foregroundStyle(phase.secondaryText)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.forward").font(.caption).foregroundStyle(phase.secondaryText)
                                    }
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button { onToggle(shown) } label: {
                    HStack {
                        Text(isSelected(shown) ? "Remove from workout" : "Add to workout")
                        Spacer()
                        Image(systemName: isSelected(shown) ? "minus.circle" : "plus.circle")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(phase.canvasStart)
            }
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .repbaseScreen(.prepare)
        }
        .presentationDetents([.large])
    }

    private var tags: [String] {
        [shown.equipmentKind?.title, shown.type?.title, shown.pattern?.title, shown.difficulty?.title]
            .compactMap { $0 } + shown.disciplineKinds.map(\.title)
    }

    @ViewBuilder
    private var muscles: some View {
        if !shown.primary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Muscles worked").font(.community(.headline))
                Text("Primary: \(shown.primary.map(\.title).joined(separator: ", "))")
                    .font(.community(.subheadline))
                if !shown.secondary.isEmpty {
                    Text("Secondary: \(shown.secondary.map(\.title).joined(separator: ", "))")
                        .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
                }
            }
        }
    }
}
