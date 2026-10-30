//
//  ActivityPicker.swift
//  IOS Frontend
//
//  Choosing what kind of workout this is, out of every activity Rytivo
//  knows.
//

import SwiftUI

/// The common activities as a grid, and the rest a tap away.
///
/// Ten tiles cover most of what people do. Everything else is in a sheet with
/// search and groups, so the builder's first screen stays short while still
/// reaching volleyball or climbing in two taps. The current choice always
/// has a tile, even when it is not one of the ten.
struct ActivityPicker: View {
    @Binding var selection: WorkoutActivity
    var phase: WorkoutVisualPhase = .prepare
    @State private var browsing = false

    private var tiles: [WorkoutActivity] {
        WorkoutActivity.featured.contains(selection)
            ? WorkoutActivity.featured
            : [selection] + WorkoutActivity.featured.dropLast()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(tiles) { activity in
                    ActivityTile(activity: activity, selected: selection == activity, phase: phase) {
                        selection = activity
                    }
                }
            }
            Button { browsing = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2")
                    Text("All activities")
                        .font(.community(.subheadline, weight: .bold))
                    Text("\(WorkoutActivity.allCases.count)")
                        .font(.community(.caption, weight: .semibold).monospacedDigit())
                        .foregroundStyle(phase.secondaryText)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.caption)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 52)
                .workoutOutline()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Search tennis, soccer, yoga, climbing and more")
        }
        .sheet(isPresented: $browsing) {
            ActivityPickerSheet(selection: $selection, phase: phase)
        }
    }
}

private struct ActivityTile: View {
    let activity: WorkoutActivity
    let selected: Bool
    let phase: WorkoutVisualPhase
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: activity.symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? phase.accent : phase.secondaryText)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text(activity.title)
                    .font(.community(.subheadline, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 64)
            .workoutOutline(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("activity-\(activity.rawValue)")
    }
}

/// Every activity, searchable and grouped.
struct ActivityPickerSheet: View {
    @Binding var selection: WorkoutActivity
    var phase: WorkoutVisualPhase = .prepare
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ForEach(ActivityCategory.allCases) { category in
                        Section(category.title) {
                            ForEach(category.activities) { row($0) }
                        }
                    }
                } else {
                    let results = WorkoutActivity.matching(query)
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        Section { ForEach(results) { row($0) } }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search activities")
            .navigationTitle("Choose an activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func row(_ activity: WorkoutActivity) -> some View {
        Button {
            selection = activity
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: activity.symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(phase.accent)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title).font(.community(.body, weight: .semibold))
                    Text(activity.trackingSummary)
                        .font(.community(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if selection == activity {
                    Image(systemName: "checkmark").foregroundStyle(phase.accent)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == activity ? [.isSelected] : [])
    }
}

extension WorkoutActivity {
    /// What logging this activity involves, in a few words.
    var trackingSummary: String {
        switch profile {
        case .strength:
            String(localized: "Exercises, sets, reps and weight", bundle: .app, locale: .app)
        case .distance:
            tracksRoute
                ? String(localized: "Time, distance and pace · GPS", bundle: .app, locale: .app)
                : String(localized: "Time, distance and pace", bundle: .app, locale: .app)
        case .session:
            String(localized: "Time and effort", bundle: .app, locale: .app)
        }
    }
}
