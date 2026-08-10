//
//  WorkoutsView.swift
//  IOS Frontend
//
//  The Workouts page — navigation destination for the weekly schedule widget.
//

import SwiftUI

/// The Workouts page.
///
/// Minimal for now: it exists so the weekly schedule widget has a real
/// navigation destination, and it reads from the same `WorkoutStore` single
/// source of truth. This will be built out in a later feature pass.
struct WorkoutsView: View {
    @Environment(WorkoutStore.self) private var store

    var body: some View {
        List {
            Section("This Week") {
                ForEach(Weekday.allCases) { day in
                    HStack {
                        Text(day.fullName)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let workout = store.workout(on: day) {
                            Text(workout.name)
                                .fontWeight(.medium)
                        } else {
                            Text("Rest")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Workouts")
    }
}

#Preview {
    NavigationStack {
        WorkoutsView()
    }
    .environment(WorkoutStore())
}
