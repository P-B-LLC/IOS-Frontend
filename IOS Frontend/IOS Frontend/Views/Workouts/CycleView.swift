//
//  CycleView.swift
//  IOS Frontend
//
//  A split that repeats every N days rather than every week.
//
//  The thing an eight-day split makes hard is knowing which day you are on,
//  because it is never the same weekday twice running. So that answer is the
//  largest thing on the screen, and everything else supports it.
//

import SwiftUI

struct CycleView: View {
    @Environment(CycleStore.self) private var store

    @State private var editing: CycleEditorView.Mode?
    @State private var isConfirmingEnd = false

    private let phase = WorkoutVisualPhase.prepare

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error = store.persistenceError {
                    Text(error)
                        .font(.community(.footnote))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if store.isLoading && store.cycles.isEmpty {
                    ProgressView("Loading your rotation...")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else if let cycle = store.activeCycle {
                    todayCard(cycle)
                    if let outcome = store.lastShift {
                        shiftReceipt(outcome)
                    }
                    offScheduleCard
                    rotationList(cycle)
                    footer(cycle)
                } else {
                    explainer
                    startButton
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .repbaseScreen(.prepare)
        .navigationTitle("Rotation")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $editing) { mode in
            NavigationStack {
                CycleEditorView(mode: mode)
            }
        }
        .task {
            // Which day of the cycle it is changes at midnight without anyone
            // touching the app, so the position is re-read on arrival rather
            // than trusted from whenever the store last loaded.
            await store.refresh()
        }
    }

    // MARK: - Where you are

    private func todayCard(_ cycle: WorkoutCycle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TODAY")
                    .font(.community(.caption2, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(phase.secondaryText)
                Spacer()
                Text(cycle.positionText)
                    .font(.community(.caption, weight: .bold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(phase.accent.opacity(0.16), in: Capsule())
                    .foregroundStyle(phase.accent)
            }

            Text(cycle.currentWorkoutName)
                .font(.community(.largeTitle, weight: .bold))
                .foregroundStyle(phase.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            Text(nextLine(cycle))
                .font(.community(.subheadline))
                .foregroundStyle(phase.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !cycle.name.isEmpty {
                Text(cycle.name)
                    .font(.community(.footnote, weight: .semibold))
                    .foregroundStyle(phase.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 18)
        .padding(.vertical, 18)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(phase.accent).frame(width: 4)
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    /// What is coming, said as a date rather than a countdown. On a rotation
    /// the useful question is which day it lands on, since it is a different
    /// weekday each turn.
    private func nextLine(_ cycle: WorkoutCycle) -> String {
        guard let date = cycle.nextWorkoutDate, !cycle.nextWorkoutName.isEmpty else {
            return "No workouts in this rotation yet."
        }
        let day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if Calendar.current.isDateInToday(date) {
            return "\(cycle.nextWorkoutName) is due today."
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "Next: \(cycle.nextWorkoutName), tomorrow."
        }
        return "Next: \(cycle.nextWorkoutName) on \(day)."
    }

    // MARK: - Getting back on schedule

    private var offScheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Off schedule?")
                .font(.community(.headline))
                .foregroundStyle(phase.primaryText)

            shiftButton(
                title: "I rested today",
                detail: "Pushes the rest of the rotation back a day. Nothing is skipped.",
                symbol: "arrow.right.to.line",
                action: { await store.restedToday() }
            )

            shiftButton(
                title: "Resume today",
                detail: "You have missed a few days. Start the workout you owe today, and carry on from there.",
                symbol: "arrow.counterclockwise",
                action: { await store.resumeToday() }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func shiftButton(
        title: String,
        detail: String,
        symbol: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.community(size: 15, weight: .semibold))
                    .foregroundStyle(phase.accent)
                    .frame(width: 26, height: 26)
                    .background(phase.accent.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.community(.subheadline, weight: .semibold))
                        .foregroundStyle(phase.primaryText)
                    Text(detail)
                        .font(.community(.caption))
                        .foregroundStyle(phase.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(store.isSaving)
        .opacity(store.isSaving ? 0.55 : 1)
    }

    /// What the shift actually did. A plan quietly rearranging itself is
    /// unsettling; saying how many days moved, and how many were left alone
    /// because something had already happened on them, is not.
    private func shiftReceipt(_ outcome: CycleShiftOutcome) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(RepbaseDesign.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(receiptTitle(outcome))
                    .font(.community(.footnote, weight: .semibold))
                    .foregroundStyle(phase.primaryText)
                Text(receiptDetail(outcome))
                    .font(.community(.caption))
                    .foregroundStyle(phase.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                store.lastShift = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.community(.caption, weight: .bold))
                    .foregroundStyle(phase.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RepbaseDesign.success.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func receiptTitle(_ outcome: CycleShiftOutcome) -> String {
        let days = outcome.daysShifted
        if days == 0 { return "Already on schedule." }
        return days == 1 ? "Pushed back a day." : "Pushed back \(days) days."
    }

    private func receiptDetail(_ outcome: CycleShiftOutcome) -> String {
        var parts = ["\(outcome.scheduled) \(outcome.scheduled == 1 ? "day" : "days") rescheduled"]
        if outcome.kept > 0 {
            // Days already trained, or ones the user put there by hand. They
            // are left where they are, and it matters that this is visible:
            // the plan will look out of step with the rule otherwise.
            parts.append("\(outcome.kept) left alone")
        }
        return parts.joined(separator: ", ") + "."
    }

    // MARK: - The rotation itself

    private func rotationList(_ cycle: WorkoutCycle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THE ROTATION")
                .font(.community(.caption2, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(phase.secondaryText)
                .padding(.horizontal, 16)
                .padding(.top, 15)
                .padding(.bottom, 10)

            let days = upcoming(cycle)
            ForEach(Array(days.enumerated()), id: \.element.slot.position) { index, day in
                CycleSlotRow(
                    slot: day.slot,
                    date: day.date,
                    isToday: index == 0,
                    phase: phase
                )
                if index != days.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cycleSurface(radius: 20, phase: phase)
    }

    /// One turn of the rotation, starting from today rather than from day one.
    ///
    /// In cycle order the dates run backwards partway down: on day 3 of 8,
    /// day 1 is six days out while day 4 is tomorrow, so the list reads as
    /// broken. Starting at today makes it a schedule you can read downwards,
    /// and the numbered badges still say where in the turn each day falls.
    private func upcoming(
        _ cycle: WorkoutCycle
    ) -> [(slot: WorkoutCycleSlot, date: Date)] {
        let slots = cycle.orderedSlots
        let length = max(min(cycle.length, slots.count), 1)
        // Positions count from one, and the server's answer is trusted but
        // not assumed to be in range.
        let start = min(max(cycle.currentPosition, 1), length) - 1
        let today = Calendar.current.startOfDay(for: Date())

        return (0..<length).compactMap { offset in
            guard let date = Calendar.current.date(
                byAdding: .day, value: offset, to: today
            ) else { return nil }
            return (slots[(start + offset) % length], date)
        }
    }

    private func footer(_ cycle: WorkoutCycle) -> some View {
        VStack(spacing: 10) {
            Button {
                editing = .edit(cycle)
            } label: {
                Label("Edit rotation", systemImage: "slider.horizontal.3")
                    .font(.community(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)

            // Only worth offering once there is something to switch to.
            if !store.otherCycles.isEmpty {
                NavigationLink {
                    RotationPickerView()
                } label: {
                    Label("Switch rotation", systemImage: "arrow.triangle.2.circlepath")
                        .font(.community(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive) {
                isConfirmingEnd = true
            } label: {
                Text("Stop using this rotation")
                    .font(.community(.footnote, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(RepbaseDesign.danger)
        }
        .disabled(store.isSaving)
        .confirmationDialog(
            "Stop using this rotation?",
            isPresented: $isConfirmingEnd,
            titleVisibility: .visible
        ) {
            Button("Stop the rotation", role: .destructive) {
                Task { await store.end(cycle) }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Workouts you have already done stay in your history. Days this rotation had planned but you have not trained yet are cleared.")
        }
    }

    // MARK: - Nothing set up yet

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.community(size: 26, weight: .semibold))
                .foregroundStyle(phase.accent)

            Text("Train on a repeating cycle")
                .font(.community(.title3, weight: .bold))
                .foregroundStyle(phase.primaryText)

            Text("A weekly plan puts the same workout on the same weekday. A rotation repeats every so many days instead — so a six-on, two-off split runs on an eight-day turn and drifts across the week, the way it is meant to.")
                .font(.community(.subheadline))
                .foregroundStyle(phase.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Rytivo keeps track of which day of the cycle you are on, and can push everything back if you take a rest day you had not planned.")
                .font(.community(.subheadline))
                .foregroundStyle(phase.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .cycleSurface(radius: 22, phase: phase)
    }

    private var startButton: some View {
        Button {
            editing = .create
        } label: {
            Label("Set up a rotation", systemImage: "plus")
                .font(.community(.subheadline, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .buttonStyle(.borderedProminent)
        .tint(phase.accent)
        .disabled(!store.isConnected)
    }
}

/// One day of the rotation.
private struct CycleSlotRow: View {
    let slot: WorkoutCycleSlot
    let date: Date?
    let isToday: Bool
    let phase: WorkoutVisualPhase

    var body: some View {
        HStack(spacing: 13) {
            Text("\(slot.position)")
                .font(.community(.footnote, weight: .bold))
                .foregroundStyle(isToday ? Color.white : phase.secondaryText)
                .frame(width: 28, height: 28)
                .background(
                    // Derived from the text colour rather than a fixed
                    // oatmeal, for the same reason the card is: a light disc
                    // under theme-coloured digits disappears in dark mode.
                    Circle().fill(
                        isToday ? phase.accent : phase.primaryText.opacity(0.10)
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(slot.displayName)
                    .font(.community(.subheadline, weight: slot.isRest ? .regular : .semibold))
                    .foregroundStyle(slot.isRest ? phase.secondaryText : phase.primaryText)
                if let date {
                    Text(
                        isToday
                            ? "Today"
                            : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    )
                    .font(.community(.caption2))
                    .foregroundStyle(phase.secondaryText)
                }
            }

            Spacer(minLength: 0)

            if isToday {
                Text("TODAY")
                    .font(.community(.caption2, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(phase.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The card the training screens use.
    ///
    /// Takes the phase because it has to: the surface used to be a fixed
    /// light paper while the text on it came from the theme, so in dark mode
    /// the card stayed pale and the words on it went pale with the rest of the
    /// app -- white on near-white, and the rotation was unreadable. Surface,
    /// border and shadow all come from the same theme as the text now, which
    /// is the only way the two can be relied on to contrast.
    func cycleSurface(
        radius: CGFloat,
        phase: WorkoutVisualPhase
    ) -> some View {
        background(
            phase.surfaceStart,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(phase.cardBorder, lineWidth: 1)
        }
        .shadow(color: phase.shadow, radius: 18, x: 0, y: 8)
    }
}
