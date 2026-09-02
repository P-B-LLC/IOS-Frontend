//
//  StepsWidget.swift
//  IOS Frontend
//
//  Steps from Apple Health, as the server holds them.
//
//  The card appears only when there are steps to draw. Asking for Health
//  access is Apple's sheet and nothing else: a card explaining that Health has
//  not answered, or offering a button to ask, is still a card on the screen,
//  and the screen is not where that conversation belongs.
//

import SwiftUI

struct StepsWidget: View {
    /// Whether to say something when there are no steps.
    ///
    /// Home stays quiet: a card there explaining that Health has not answered
    /// is noise on a page nobody opened to think about Health. The workout
    /// page is where steps are the point, so there it says how to turn them
    /// on rather than leaving a gap.
    var explainsWhenEmpty: Bool = false
    /// The training dashboard uses the glanceable single-row treatment. Home
    /// keeps the seven-day history card.
    var compact: Bool = false

    @Environment(ActivityStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    @State private var isEditingGoal = false
    /// Held while the sheet is open so cancelling leaves the saved goal alone.
    @State private var goalDraft = 8_000

    /// "8K GOAL" while the number is round, the full figure when it is not:
    /// 8,500 shown as "8K" would be wrong, and "8.5K" is harder to read at
    /// nine points than the number itself.
    static func goalText(_ goal: Int) -> String {
        goal % 1_000 == 0
            ? "\(goal / 1_000)K GOAL"
            : "\(goal.formatted(.number)) GOAL"
    }

    var body: some View {
        if store.week.isEmpty == false {
            if compact { compactCard } else { card.padding(.top, 22) }
        } else if explainsWhenEmpty, store.isHealthSupported {
            connectCard
                .padding(.top, 22)
        }
    }

    private var compactCard: some View {
        let goal = store.stepGoal
        let steps = store.stepsToday ?? 0
        let progress = min(Double(steps) / Double(goal), 1)
        let remaining = max(goal - steps, 0)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY'S MOVEMENT")
                        .font(.community(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(RepbaseDesign.success)

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(steps.formatted(.number))
                            .font(.community(.title2, weight: .bold))
                            .contentTransition(.numericText())
                        Text("steps today")
                            .font(.community(.caption2, weight: .medium))
                            .foregroundStyle(timeOfDay.secondaryText)
                    }
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 2) {
                    Button {
                        goalDraft = goal
                        isEditingGoal = true
                    } label: {
                        HStack(spacing: 3) {
                            Text(Self.goalText(goal))
                                .font(.community(size: 9, weight: .bold))
                            Image(systemName: "pencil")
                                .font(.community(size: 7, weight: .bold))
                        }
                        .foregroundStyle(RepbaseDesign.success)
                        // A label this small is hard to hit, so the target is
                        // padded well past what is drawn.
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "Change your daily step goal, currently \(goal.formatted(.number))"
                    )
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.community(.caption2, weight: .semibold))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
            }

            GeometryReader { proxy in
                let markerX = max(7, min(proxy.size.width - 7, proxy.size.width * progress))
                ZStack(alignment: .leading) {
                    Capsule().fill(RepbaseDesign.success.opacity(0.18)).frame(height: 3)
                    Capsule().fill(RepbaseDesign.success).frame(width: markerX, height: 3)
                    ForEach(0...4, id: \.self) { index in
                        Circle()
                            .fill(Double(index) / 4 <= progress ? RepbaseDesign.success : RepbasePalette.paper)
                            .overlay(Circle().stroke(RepbaseDesign.success.opacity(0.22), lineWidth: 1))
                            .frame(width: 9, height: 9)
                            .position(x: proxy.size.width * CGFloat(index) / 4, y: 11)
                    }
                    Circle()
                        .fill(RepbaseDesign.accent)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(RepbaseDesign.accent.opacity(0.24), lineWidth: 4))
                        .position(x: markerX, y: 11)
                }
            }
            .frame(height: 22)

            Text(remaining == 0 ? "Goal reached" : "\(remaining.formatted(.number)) to go")
            .font(.community(size: 9, weight: .semibold))
            .foregroundStyle(RepbaseDesign.success)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) { Divider() }
        .task { await store.refresh() }
        // Not combined into one element, or the goal button disappears from
        // VoiceOver along with everything else on the row.
        .accessibilityLabel("\(steps.formatted(.number)) steps today, \(progress.formatted(.percent)) of goal")
        .sheet(isPresented: $isEditingGoal) {
            StepGoalEditor(goal: $goalDraft) { chosen in
                Task { await store.updateStepGoal(chosen) }
            }
        }
    }

    private func compactInsight(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.community(.caption, weight: .bold))
            Text(label)
                .font(.community(size: 8, weight: .bold))
                .tracking(0.45)
                .foregroundStyle(timeOfDay.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var changeText: String {
        guard let change = store.latestDayChange else { return "—" }
        if change == 0 { return "Even" }
        return "\(change > 0 ? "+" : "")\(change.formatted(.number))"
    }

    /// Shown when there are no steps to draw.
    ///
    /// Tappable only before Apple's sheet has been shown. Afterwards iOS shows
    /// nothing at all on a second request, so a button would be a control that
    /// visibly does nothing; the text points at Settings instead.
    @ViewBuilder
    private var connectCard: some View {
        if store.hasAskedHealth {
            connectBody(
                message: "No steps from Health yet. Turn Rytivo on under Settings, Privacy & Security, Health.",
                action: nil
            )
        } else {
            connectBody(
                message: "Connect to Apple Health to see steps.",
                action: { Task { await store.connectHealth() } }
            )
        }
    }

    private func connectBody(
        message: String,
        action: (() -> Void)?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.walk")
                .font(.community(size: 12, weight: .bold))
                .foregroundStyle(timeOfDay.accent)
                .frame(width: 28, height: 28)
                .background(
                    timeOfDay.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            Text(message)
                .font(.community(.footnote))
                .foregroundStyle(timeOfDay.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if store.isRequestingHealthAccess {
                ProgressView().controlSize(.small)
            } else if action != nil {
                Image(systemName: "chevron.forward")
                    .font(.community(.caption, weight: .bold))
                    .foregroundStyle(timeOfDay.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .repbaseDepthSurface(cornerRadius: RepbaseDesign.featureRadius)
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(timeOfDay.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { action?() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(action == nil ? [] : .isButton)
        .task {
            // The card with steps in it refreshes on appear; this one has to
            // as well, or access granted in Settings would never be noticed
            // and the card would keep asking for something already given.
            await store.refresh()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            todayCount
            weekStrip
            importNote
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(timeOfDay.primaryText)
        .repbaseDepthSurface(cornerRadius: RepbaseDesign.featureRadius)
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(timeOfDay.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .task {
            // Health backfills: a watch that synced late changes yesterday's
            // total too, so returning to Home asks again rather than trusting
            // whatever was true when the app launched.
            await store.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.community(size: 12, weight: .bold))
                .foregroundStyle(timeOfDay.accent)
                .frame(width: 28, height: 28)
                .background(
                    timeOfDay.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            Text("Steps")
                .font(.community(size: 16, weight: .semibold, design: .rounded))
            Spacer()
            if store.isSyncing {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var todayCount: some View {
        if let steps = store.stepsToday {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(steps.formatted(.number))
                    .font(.community(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("today")
                    .font(.community(.footnote, weight: .medium))
                    .foregroundStyle(timeOfDay.secondaryText)
            }
        } else {
            // The server has days, but not this one. Saying "0" would claim
            // the user has not moved; they may simply not have carried their
            // phone yet today.
            Text("No steps recorded today yet")
                .font(.community(.footnote, weight: .medium))
                .foregroundStyle(timeOfDay.secondaryText)
        }
    }

    private var weekStrip: some View {
        let peak = max(store.weekPeak ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(lastSevenDays, id: \.self) { day in
                let steps = store.week.first { $0.day == day }?.steps
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            steps == nil
                                ? timeOfDay.accent.opacity(0.10)
                                : timeOfDay.accent.opacity(isToday(day) ? 1 : 0.45)
                        )
                        .frame(
                            height: max(
                                4,
                                CGFloat(steps ?? 0) / CGFloat(peak) * 54
                            )
                        )
                    Text(weekdayInitial(day))
                        .font(.community(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 74, alignment: .bottom)
        .accessibilityLabel(weekAccessibilityLabel)
    }

    /// What the last import did, when it did anything.
    ///
    /// The skipped line is worth saying out loud. A run tracked in Repbase and
    /// recorded by the Watch is one run, and silently dropping the duplicate
    /// would look like the import missing workouts rather than declining to
    /// count them twice.
    @ViewBuilder
    private var importNote: some View {
        if let summary = store.lastImport,
           summary.imported > 0 || summary.skippedOverlapping > 0 {
            VStack(alignment: .leading, spacing: 3) {
                if summary.imported > 0 {
                    Text("\(summary.imported) \(workoutWord(summary.imported)) brought in from Health")
                }
                if summary.skippedOverlapping > 0 {
                    Text("\(summary.skippedOverlapping) \(workoutWord(summary.skippedOverlapping)) skipped, already recorded here")
                }
            }
            .font(.community(.caption))
            .foregroundStyle(timeOfDay.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func workoutWord(_ count: Int) -> String {
        count == 1 ? "workout" : "workouts"
    }

    // MARK: - Days

    /// The seven days ending today, oldest first. Built from the calendar
    /// rather than from what came back, so a day with no steps still gets a
    /// column and the strip does not silently shorten.
    private var lastSevenDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<ActivityStore.historyDays)
            .reversed()
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private func isToday(_ day: Date) -> Bool {
        Calendar.current.isDateInToday(day)
    }

    private func weekdayInitial(_ day: Date) -> String {
        let index = Calendar.current.component(.weekday, from: day) - 1
        let symbols = Calendar.current.veryShortWeekdaySymbols
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    private var weekAccessibilityLabel: String {
        let counted = store.week.count
        guard counted > 0 else { return "No steps in the last seven days" }
        let total = store.week.reduce(0) { $0 + $1.steps }
        return "\(total.formatted(.number)) steps across \(counted) of the last seven days"
    }
}

/// Setting the daily step goal.
///
/// A stepper in round hundreds rather than a free text field: the goal is a
/// round target, not a measurement, and a keyboard invites "8" or "80000".
/// The bounds match what the server accepts, so the sheet cannot compose a
/// request the API will refuse.
private struct StepGoalEditor: View {
    @Binding var goal: Int
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.homeTimeOfDay) private var timeOfDay

    private static let lowest = 1_000
    private static let highest = 100_000
    private static let step = 500

    var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                VStack(spacing: 6) {
                    Text(goal.formatted(.number))
                        .font(.community(size: 46, weight: .bold))
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.15), value: goal)
                    Text("steps a day")
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
                .padding(.top, 20)

                Stepper(
                    value: $goal,
                    in: Self.lowest...Self.highest,
                    step: Self.step
                ) {
                    Text("Adjust")
                        .font(.community(.subheadline, weight: .semibold))
                }
                .padding(.horizontal, RepbaseDesign.pageInset)

                // The usual answers, so the common case is one tap rather
                // than twenty on a stepper.
                HStack(spacing: 8) {
                    ForEach([5_000, 8_000, 10_000, 12_000], id: \.self) { preset in
                        Button {
                            goal = preset
                        } label: {
                            Text("\(preset / 1_000)K")
                                .font(.community(.footnote, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    goal == preset
                                        ? RepbaseDesign.success.opacity(0.18)
                                        : timeOfDay.primaryText.opacity(0.06),
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    goal == preset
                                        ? RepbaseDesign.success
                                        : timeOfDay.primaryText
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, RepbaseDesign.pageInset)

                Spacer(minLength: 0)
            }
            .navigationTitle("Daily step goal")
            .navigationBarTitleDisplayMode(.inline)
            .homeTimeScreen(timeOfDay)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(goal)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(340)])
    }
}
