//
//  SavedWorkoutsView.swift
//  IOS Frontend
//
//  The workouts already built: find one, start it, plan it, edit or copy it.
//
//  Reusing one schedules it. The template is not copied, rewritten, or moved:
//  its exercises, the rows joining them to it, and their target sets stay
//  exactly as they are, and it keeps whatever other days it is already
//  planned on. Copying is its own explicit action, which makes a new workout.
//

import Foundation
import SwiftUI

struct SavedWorkoutsView: View {
    private enum Sort: String, CaseIterable, Identifiable {
        case recent, name
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .recent: "Recent"
            case .name: "A–Z"
            }
        }
    }

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var sort: Sort = .recent
    @State private var planning: WorkoutSummary?
    @State private var editing: WorkoutSummary?
    @State private var deleting: WorkoutSummary?
    @State private var busyID: Int?
    @State private var failureMessage: String?
    @State private var openedDay: Weekday?
    @State private var confirmation: String?

    private var workouts: [WorkoutSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = store.knownWorkouts.filter {
            trimmed.isEmpty
                || $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.exercises.contains { $0.name.localizedCaseInsensitiveContains(trimmed) }
        }
        switch sort {
        case .name:
            return matching.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recent:
            // Most recently trained first; never-trained ones after, by name.
            return matching.sorted {
                switch ($0.lastPerformedAt, $1.lastPerformedAt) {
                case let (a?, b?): return a > b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RepbaseScreenHeader(
                    eyebrow: "YOUR LIBRARY",
                    title: "Saved workouts",
                    detail: "Start one now, plan it on a day, or make it better."
                )

                if store.knownWorkouts.count > 3 {
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search workouts or exercises", text: $query)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .workoutOutline()
                        Picker("Sort", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 128)
                    }
                }

                if let message = failureMessage ?? store.persistenceError {
                    // The server's refusal, which names the rotation in the way.
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.community(.footnote))
                        .foregroundStyle(RepbaseDesign.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .font(.community(.footnote, weight: .semibold))
                        .foregroundStyle(RepbaseDesign.success)
                        .transition(.opacity)
                }

                if store.knownWorkouts.isEmpty {
                    empty
                } else if workouts.isEmpty {
                    Text("No saved workout matches “\(query)”.")
                        .font(.community(.subheadline)).foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(workouts) { workout in card(workout) }
                    }
                    Text("Deleting a saved workout also removes the days it is planned on. Training you have already done stays in your history, and a workout a rotation is built from cannot be deleted until the rotation changes.")
                        .font(.community(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .repbaseScreen(.prepare)
        .navigationTitle("Saved workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .navigationDestination(item: $openedDay) { day in DayWorkoutView(day: day) }
        .sheet(item: $planning) { workout in
            PlanOnDaySheet(workout: workout) { message in
                withAnimation { confirmation = message }
            }
        }
        .fullScreenCover(item: $editing) { workout in
            WorkoutEditorView(
                mode: .edit(workout.asWorkout),
                suggestions: store.knownWorkouts,
                recoveryContext: "library"
            ) { edited in
                await store.updateSavedWorkout(edited)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No saved workouts yet")
                .font(.community(.subheadline, weight: .semibold))
            Text("Build a workout on any day and it will be here to reuse.")
                .font(.community(.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - A workout

    private func card(_ workout: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ActivityIconArtwork(kind: workout.type.activityIcon, size: 20, color: RepbasePalette.caramel)
                    .frame(width: 38, height: 38)
                    .background(RepbasePalette.caramel.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.name)
                        .font(.community(.headline))
                        .lineLimit(2)
                    Text(detail(workout))
                        .font(.community(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                menu(workout)
            }
            .contentShape(Rectangle())
            .onTapGesture { editing = workout }
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: "Edit") { editing = workout }

            if let preview = preview(workout) {
                Text(preview)
                    .font(.community(.subheadline))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Image(systemName: workout.lastPerformedAt == nil ? "sparkles" : "clock.arrow.circlepath")
                Text(lastDone(workout))
            }
            .font(.community(.caption))
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    Task { await start(workout) }
                } label: {
                    HStack(spacing: 6) {
                        if busyID == workout.serverID { ProgressView().tint(WorkoutVisualPhase.prepare.onPrimaryAction) }
                        Image(systemName: "play.fill")
                        Text(store.activeSession == nil ? "Start" : "Continue workout")
                    }
                    .font(.community(.subheadline, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .foregroundStyle(WorkoutVisualPhase.prepare.onPrimaryAction)
                    .background(WorkoutVisualPhase.prepare.primaryActionSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busyID != nil || store.isSaving || (store.activeSession != nil && store.activeSession?.workoutServerID != workout.serverID))

                Button { planning = workout } label: {
                    Label("Add to a day", systemImage: "calendar.badge.plus")
                        .font(.community(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(WorkoutVisualPhase.prepare.cardBorder.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busyID != nil || store.isSaving)
            }
            .frame(minHeight: 44)
        }
        .padding(14)
        .workoutOutline(radius: 18)
        // On the card itself, so the question appears beside the workout it
        // is about. Attached to the list, it was drawn over the first card
        // whichever workout was being deleted.
        .confirmationDialog(
            "Delete this saved workout?",
            isPresented: Binding(
                get: { deleting?.serverID == workout.serverID },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete \(workout.name)", role: .destructive) {
                Task { await store.deleteSavedWorkout(workout) }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The days it is planned on are removed too. Workouts you already trained stay in your history.")
        }
    }

    private func menu(_ workout: WorkoutSummary) -> some View {
        Menu {
            Button { editing = workout } label: { Label("Edit", systemImage: "pencil") }
            Button {
                Task { await duplicate(workout) }
            } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { planning = workout } label: { Label("Add to a day", systemImage: "calendar.badge.plus") }
            Divider()
            // Set apart and confirmed: it removes the days the workout is
            // planned on as well, and is the one action here that cannot be
            // taken back.
            Button(role: .destructive) { deleting = workout } label: { Label("Delete", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.community(.subheadline, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(store.isSaving)
        .accessibilityLabel("Options for \(workout.name)")
    }

    private func detail(_ workout: WorkoutSummary) -> String {
        guard !workout.exercises.isEmpty, workout.activity.usesSets else { return workout.activity.title }
        let minutes = WorkoutSetPolicy.estimatedMinutes(
            sets: workout.exercises.map { ($0.sets, $0.restSeconds) },
            defaultRestSeconds: store.preferences.defaultRestSeconds
        )
        return String(
            localized: "\(workout.exercises.count) exercises · \(workout.totalSets) sets · about \(minutes) min",
            bundle: .app,
            locale: .app
        )
    }

    /// The first few exercise names, so a workout is recognised by what is in
    /// it rather than by its name alone.
    private func preview(_ workout: WorkoutSummary) -> String? {
        let names = workout.exercises.map(\.name)
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(3).joined(separator: ", ")
        guard names.count > 3 else { return shown }
        return String(
            localized: "\(shown) +\(names.count - 3) more",
            bundle: .app,
            locale: .app,
            comment: "Exercise names, then how many more there are"
        )
    }

    private func lastDone(_ workout: WorkoutSummary) -> String {
        guard let date = workout.lastPerformedAt else {
            return String(localized: "Not trained yet", bundle: .app, locale: .app)
        }
        let relative = date.formatted(.relative(presentation: .named).locale(.app))
        return String(localized: "Last done \(relative)", bundle: .app, locale: .app, comment: "When a workout was last trained, such as “Last done 3 days ago”")
    }

    // MARK: - Actions

    private func start(_ workout: WorkoutSummary) async {
        if let session = store.activeSession {
            openedDay = session.day
            return
        }
        guard busyID == nil else { return }
        busyID = workout.serverID
        failureMessage = nil
        defer { busyID = nil }
        if let day = await store.startSavedWorkout(workout) {
            openedDay = day
        } else {
            failureMessage = store.persistenceError
                ?? String(localized: "That workout could not be started.", bundle: .app, locale: .app)
        }
    }

    private func duplicate(_ workout: WorkoutSummary) async {
        guard busyID == nil else { return }
        busyID = workout.serverID
        failureMessage = nil
        defer { busyID = nil }
        if await store.duplicateSavedWorkout(workout) != nil {
            withAnimation {
                confirmation = String(localized: "Copied \(workout.name).", bundle: .app, locale: .app)
            }
        }
    }
}

/// Puts a saved workout on a chosen day.
private struct PlanOnDaySheet: View {
    let workout: WorkoutSummary
    let onPlanned: (String) -> Void
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var scheduling = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(workout.name).font(.community(.title3, weight: .bold))
                DatePicker("Day", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                if let failure {
                    Text(failure).font(.community(.footnote)).foregroundStyle(RepbaseDesign.warning)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Add to a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await add() }
                    } label: {
                        if scheduling { ProgressView() } else { Text("Add") }
                    }
                    // One at a time. Two taps in flight would schedule the
                    // same workout on the same day twice.
                    .disabled(scheduling || store.isSaving)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func add() async {
        guard !scheduling else { return }
        scheduling = true
        failure = nil
        defer { scheduling = false }
        if await store.scheduleKnownWorkout(workout, on: date) {
            onPlanned(String(
                localized: "\(workout.name) added to \(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(.app))).",
                bundle: .app,
                locale: .app
            ))
            dismiss()
        } else {
            // Stays open, saying so. Closing on a failure would look like it
            // worked until the day was opened and found empty.
            failure = store.persistenceError
                ?? String(localized: "That workout could not be added to the day.", bundle: .app, locale: .app)
        }
    }
}
