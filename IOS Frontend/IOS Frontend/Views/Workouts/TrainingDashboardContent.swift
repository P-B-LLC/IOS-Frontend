//
//  TrainingDashboardContent.swift
//  IOS Frontend
//
//  The approved soft-luxury training dashboard. Existing navigation and
//  actions are preserved; every statistic is derived from API-owned records.
//

import Foundation
import SwiftUI

struct TrainingDashboardContent: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(CycleStore.self) private var cycles
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isConfirmingClear = false
    @State private var displayedCompletedThisWeek: Int?
    @State private var displayedTotalWorkouts: Int?
    @State private var hiddenCompletedDay: Weekday?
    @State private var rewardIsVisible = false
    @State private var rewardToast: String?
    @State private var rewardTask: Task<Void, Never>?

    private var phase: WorkoutVisualPhase {
        store.activeSession == nil ? .prepare : .focus
    }

    /// Counted by the server. This used to be a reduction over every session
    /// the account had ever recorded, which is why the dashboard paged the
    /// whole history each time it appeared.
    private var metrics: TrainingStats { store.trainingStats }
    private var completedThisWeek: Int {
        displayedCompletedThisWeek ?? metrics.completedThisWeek
    }
    private var totalWorkouts: Int {
        displayedTotalWorkouts ?? metrics.totalWorkouts
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if store.recoveredActiveSession, let session = store.activeSession {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recovered \(session.workoutName)").font(.community(.headline))
                        Text("Your session is still open. Continue it or finish it from its workout day.")
                            .font(.community(.footnote))
                        NavigationLink("Open recovered session") { DayWorkoutView(day: session.day) }
                        if session.tracksDistance {
                            Button("Resume GPS tracking") { store.resumeRecoveredTracking() }
                        }
                    }
                }
                if store.pendingWorkoutSaveCount > 0 || store.recoveryError != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Workout sync pending").font(.community(.headline))
                        Text(store.recoveryError ?? String(localized: "Your workout is saved on this device until sync completes. If its session is open, tap Finish there to retry.", bundle: .app, locale: .app))
                            .font(.community(.footnote))
                        Button("Retry sync") { Task { await store.retryPendingWorkoutSaves() } }
                            .disabled(store.isRecoveringWorkouts || store.isSaving)
                        if store.isRecoveringWorkouts { ProgressView("Syncing…") }
                    }
                }
                if let persistenceError = store.persistenceError {
                    errorCard(persistenceError)
                }

                if store.isLoading {
                    ProgressView("Loading this week from Rytivo...")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                        .workoutCard()
                } else {
                    workoutPlanCard
                    focusCard
                    StepsWidget(explainsWhenEmpty: true, compact: true)
                    if metrics != .empty || (store.isConnected && store.persistenceError == nil) {
                        momentumSection
                    }
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 10)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .minimizesBottomBarOnScroll()
        .task { await store.retryPendingWorkoutSaves() }
        .overlay(alignment: .bottom) {
            if let rewardToast {
                TrainingRewardToast(message: rewardToast)
                    .padding(.horizontal, RepbaseDesign.pageInset)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear(perform: playPendingReward)
        .onDisappear {
            rewardTask?.cancel()
            rewardTask = nil
            rewardToast = nil
            rewardIsVisible = false
            displayedCompletedThisWeek = nil
            displayedTotalWorkouts = nil
            hiddenCompletedDay = nil
        }
    }

    private var workoutPlanCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            // A title and a count sharing a line, which at the accessibility
            // sizes left the title about half the card and broke it into
            // "Workou / t plan".
            AdaptiveRow(spacing: 8) {
                Text("Workout plan").font(.community(.headline))
            } trailing: {
                Text("Tap a day")
                    .font(.community(.footnote))
                    .foregroundStyle(phase.secondaryText)
            }

            HStack(alignment: .top, spacing: 4) {
                ForEach(Weekday.allCases) { day in
                    NavigationLink {
                        DayWorkoutView(day: day)
                    } label: {
                        DashboardDayItem(
                            day: day,
                            date: store.workoutDate(for: day),
                            workouts: store.workouts(on: day),
                            isToday: store.today == day,
                            isSessionActive: store.activeSession?.day == day,
                            isCompleted: isCompleted(day) && hiddenCompletedDay != day
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            // Seven days across, like every other week row in the app. Left
            // uncapped the headings came apart into stacked letters -- M, O,
            // N -- and the workout names under them truncated to "P...", so
            // the row said neither which day nor which workout.
            .typeSizeCeiling()

            // Without a rotation, the week is whatever was put there by hand,
            // and changing your mind about all of it should not mean opening
            // seven days and emptying each. With one, the rotation is what
            // fills the week and the way to change it is to change the
            // rotation -- the server refuses this then, for the same reason.
            if cycles.activeCycle == nil, store.hasAnythingScheduled {
                Button {
                    isConfirmingClear = true
                } label: {
                    Label("Clear this schedule", systemImage: "calendar.badge.minus")
                        .font(.community(.caption, weight: .semibold))
                        .foregroundStyle(phase.secondaryText)
                }
                .buttonStyle(.plain)
                .disabled(store.isSaving)
            }

            Divider()
            cycleRow
        }
        .padding(16)
        .dashboardSurface(radius: 22)
        // Asked about, unlike the per-day controls: this empties the whole
        // calendar at once and there is nothing to undo it with.
        .confirmationDialog(
            "Clear every planned workout?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear the schedule", role: .destructive) {
                Task { await store.clearSchedule() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Every workout you have planned is removed, past days included, so you can start again. Workouts you have already done stay in your history.")
        }
    }

    /// The way into rotations, and the only place the current day of one is
    /// shown without going looking for it.
    ///
    /// A row rather than a button, because it has something to say when a
    /// rotation is running: which day of it today is. That is the whole
    /// difficulty of an eight-day split, and the strip of weekdays above
    /// cannot express it.
    private var cycleRow: some View {
        NavigationLink {
            CycleView()
        } label: {
            HStack(spacing: 11) {
                if let cycle = cycles.activeCycle {
                    Text("\(cycle.currentPosition)")
                        .font(.community(.footnote, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(phase.accent))
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.community(size: 13, weight: .semibold))
                        .foregroundStyle(phase.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(RepbasePalette.oatmeal))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(cycles.activeCycle?.positionText ?? String(localized: "Repeating split", bundle: .app, locale: .app))
                        .font(.community(.subheadline, weight: .semibold))
                        .foregroundStyle(phase.primaryText)
                    Text(cycleDetail)
                        .font(.community(.caption))
                        .foregroundStyle(phase.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.forward")
                    .font(.community(.caption, weight: .semibold))
                    .foregroundStyle(phase.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cycleDetail: String {
        guard let cycle = cycles.activeCycle else {
            return String(localized: "Train on a cycle, not a weekly plan", bundle: .app, locale: .app)
        }
        return String(localized: "\(cycle.currentWorkoutDisplayName) today", bundle: .app, locale: .app, comment: "The placeholder is a workout name, or Rest on a rest day")
    }

    @ViewBuilder
    private var focusCard: some View {
        if let session = store.activeSession {
            NavigationLink {
                DayWorkoutView(day: session.day)
            } label: {
                WorkoutFocusCard(
                    eyebrow: "SESSION IN PROGRESS",
                    title: session.workoutName,
                    detail: String(localized: "\(session.loggedSetCount) of \(session.totalSetCount) sets logged", bundle: .app, locale: .app),
                    completed: metrics.completedThisWeek,
                    goal: metrics.weeklyGoal,
                    workoutType: session.workoutType
                )
            }
            .buttonStyle(.plain)
        } else if let day = store.today ?? Weekday.allCases.first {
            NavigationLink {
                DayWorkoutView(day: day)
            } label: {
                WorkoutFocusCard(
                    eyebrow: "TODAY",
                    title: store.workout(on: day)?.name ?? String(localized: "Plan today’s workout", bundle: .app, locale: .app),
                    detail: focusDescription(for: day),
                    completed: completedThisWeek,
                    goal: metrics.weeklyGoal,
                    workoutType: store.workout(on: day)?.type ?? .lifting,
                    isDayComplete: hiddenCompletedDay != day && store.workout(on: day).map {
                        store.isCompleted(
                            workoutName: $0.name,
                            on: store.workoutDate(for: day)
                        )
                    } ?? false,
                    celebratesCompletion: rewardIsVisible
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var momentumSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rewardIsVisible ? "Momentum gained." : "The bigger picture")
                    .font(.community(.title2, weight: .bold))
                    .contentTransition(.opacity)
                Text(rewardIsVisible ? "That session moved the whole week forward." : "Small efforts, seen over time.")
                    .font(.community(.footnote))
                    .foregroundStyle(phase.secondaryText)
            }

            totalsCard
            trendCard
            milestoneCard

            if store.isLoadingDashboardSessions && store.dashboardSessions.isEmpty {
                ProgressView("Loading progress from Rytivo...")
                    .font(.community(.footnote))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var totalsCard: some View {
        HStack(spacing: 0) {
            metric(
                eyebrow: "TOTAL WORKOUTS",
                value: "\(totalWorkouts)",
                detail: metrics.monthDetail,
                color: RepbaseDesign.warning
            )
            Rectangle()
                .fill(RepbasePalette.oatmeal)
                .frame(width: 1, height: 76)
            metric(
                eyebrow: "CURRENT STREAK",
                value: metrics.currentStreakText,
                detail: metrics.bestStreakWeeks == 1
                    ? String(localized: "Best: 1 week", bundle: .app, locale: .app)
                    : String(localized: "Best: \(metrics.bestStreakWeeks) weeks", bundle: .app, locale: .app),
                color: phase.secondaryText
            )
        }
        .padding(.vertical, 17)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func metric(eyebrow: LocalizedStringKey, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow)
                .font(.community(.caption2, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(phase.secondaryText)
            Text(value)
                .font(.community(.title, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(detail)
                .font(.community(.caption, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SESSION RHYTHM")
                        .font(.community(.caption2, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(phase.secondaryText)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(metrics.completedThisWeek) this week").font(.community(.title2, weight: .bold))
                        Text("\(metrics.previousWeekCount) last week")
                            .font(.community(.caption))
                            .foregroundStyle(phase.secondaryText)
                    }
                }
                Spacer()
            }

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(metrics.sixWeekCounts.enumerated()), id: \.offset) { index, count in
                    VStack(spacing: 7) {
                        Text("\(count)")
                            .font(.community(.caption2, weight: .semibold))
                            .foregroundStyle(phase.secondaryText)
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(phase.secondaryText.opacity(0.08))
                                .frame(height: 86)
                            Capsule()
                                .fill(index == 5 ? HomeTimeOfDay.current.accent : phase.secondaryText.opacity(0.6))
                                .frame(height: metrics.barHeight(for: count))
                        }
                        Text(index == 5 ? "NOW" : "−\(5 - index)W", comment: "Week chart label: NOW is this week, −2W is two weeks ago")
                            .font(.community(size: 9, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(index == 5 ? RepbaseDesign.warning : phase.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(index == 5
                        ? "This week, \(count) completed workouts"
                        : "\(5 - index) weeks ago, \(count) completed workouts")
                }
            }
            Text("Completed sessions, not weight lifted. This week is still in progress.")
                .font(.community(.caption)).foregroundStyle(phase.secondaryText)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var milestoneCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("NEXT MILESTONE")
                    .font(.community(.caption2, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(phase.secondaryText)
                Text(metrics.milestoneTitle)
                    .font(.community(.callout, weight: .semibold))
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 7) {
                ProgressView(value: metrics.milestoneProgress)
                    .tint(HomeTimeOfDay.current.accent)
                    .frame(width: 78)
                Text("\(metrics.totalWorkouts) / \(metrics.nextMilestone)")
                    .font(.community(.caption2, weight: .semibold))
                    .foregroundStyle(phase.secondaryText)
            }
        }
        .padding(.vertical, 14)
    }

    private func isCompleted(_ day: Weekday) -> Bool {
        WorkoutFocusPolicy.dayIsComplete(
            scheduledCompletions: store.workouts(on: day).map {
                store.isCompleted(workout: $0, on: store.workoutDate(for: day))
            },
            hasActiveSession: store.activeSession?.day == day
        )
    }

    private func playPendingReward() {
        guard rewardTask == nil,
              let reward = store.consumeTrainingDashboardReward() else { return }

        displayedCompletedThisWeek = reward.previousCompletedThisWeek
        displayedTotalWorkouts = reward.previousTotalWorkouts
        hiddenCompletedDay = reward.day
        rewardIsVisible = false

        rewardTask = Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(260))
            }
            guard !Task.isCancelled else { return }

            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.62, dampingFraction: 0.78)) {
                displayedCompletedThisWeek = reward.completedThisWeek
                displayedTotalWorkouts = reward.totalWorkouts
                hiddenCompletedDay = nil
                rewardIsVisible = true
                rewardToast = String(localized: "\(reward.workoutName) complete · goal moved forward", bundle: .app, locale: .app)
            }
            // The saved-session summary already celebrates the confirmed finish.

            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.24)) {
                rewardToast = nil
                rewardIsVisible = false
            }
            displayedCompletedThisWeek = nil
            displayedTotalWorkouts = nil
            rewardTask = nil
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.community(.footnote))
                .foregroundStyle(Color.orange)
            Button("Retry") { store.retryPersistence() }
                .font(.community(.footnote, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private func focusDescription(for day: Weekday) -> String {
        guard let workout = store.workout(on: day) else {
            return String(localized: "Add a name, exercises, and target sets.", bundle: .app, locale: .app)
        }
        let exercises = workout.exercises.count == 1
            ? String(localized: "1 exercise", bundle: .app, locale: .app)
            : String(localized: "\(workout.exercises.count) exercises", bundle: .app, locale: .app)
        let sets = workout.totalSets == 1
            ? String(localized: "1 target set", bundle: .app, locale: .app)
            : String(localized: "\(workout.totalSets) target sets", bundle: .app, locale: .app)
        return "\(exercises)  ·  \(sets)"
    }
}

private struct DashboardDayItem: View {
    let day: Weekday
    let date: Date
    let workouts: [Workout]
    let isToday: Bool
    let isSessionActive: Bool
    let isCompleted: Bool

    private var isPlanned: Bool { !workouts.isEmpty }

    var body: some View {
        VStack(spacing: 6) {
            Text(day.shortName.uppercased())
                .font(.community(size: 9, weight: isToday ? .bold : .semibold))
                .foregroundStyle(isToday ? RepbaseDesign.warning : Color.secondary)

            Text(date.formatted(.dateTime.day().locale(.app)))
                .font(.community(.headline, weight: .bold))
                .foregroundStyle(RepbaseDesign.ink)
            .overlay(alignment: .topTrailing) {
                if workouts.count > 1 {
                    Text("\(workouts.count)")
                        .font(.community(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(RepbaseDesign.warning, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }

            Image(systemName: dayMarkerSymbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isCompleted ? RepbaseDesign.success : RepbaseDesign.warning)
                .frame(height: 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(dayFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isToday ? RepbaseDesign.warning : dayBorder, lineWidth: isToday ? 1.5 : 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard isPlanned else { return String(localized: "\(day.fullName), add workout", bundle: .app, locale: .app) }
        let names = workouts.map(\.name).joined(separator: ", ")
        return isCompleted
            ? String(localized: "\(day.fullName), \(names), completed", bundle: .app, locale: .app, comment: "A weekday, then the names of its workouts")
            : "\(day.fullName), \(names)"
    }

    private var dayMarkerSymbol: String {
        if isCompleted { return "checkmark" }
        if isSessionActive { return "bolt.fill" }
        return isPlanned ? "minus" : "plus"
    }

    private var dayFill: Color {
        if isCompleted {
            return .repbaseDynamic(light: Color(hex: 0xDBEFE2), dark: Color(hex: 0x233C2E))
        }
        if isPlanned {
            return .repbaseDynamic(light: Color(hex: 0xFFE5D5), dark: Color(hex: 0x472C20))
        }
        return WorkoutVisualPhase.prepare.surfaceStart
    }

    private var dayBorder: Color {
        if isCompleted { return RepbaseDesign.success.opacity(0.5) }
        if isPlanned { return RepbaseDesign.warning.opacity(0.4) }
        return WorkoutVisualPhase.prepare.cardBorder
    }
}

private struct WorkoutFocusCard: View {
    let eyebrow: LocalizedStringKey
    let title: String
    let detail: String
    let completed: Int
    let goal: Int
    let workoutType: WorkoutType
    var isDayComplete = false
    var celebratesCompletion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(eyebrow).font(.community(.caption2, weight: .bold))
                Spacer()
                Image(systemName: workoutType.builderSymbol).font(.system(size: 20))
            }.foregroundStyle(RepbaseDesign.warning)
            Text(title).font(.community(.title, weight: .bold))
            Text(detail).font(.community(.caption)).foregroundStyle(.secondary)
            HStack {
                // Compares keys, which are the same whatever the language.
                Text(eyebrow == "SESSION IN PROGRESS" ? "Resume workout" : isDayComplete ? "View workout" : "Open workout")
                Spacer()
                Image(systemName: "arrow.forward")
            }
            .font(.community(.subheadline, weight: .bold))
            .foregroundStyle(WorkoutVisualPhase.prepare.onPrimaryAction)
            .padding(14)
            .background(WorkoutVisualPhase.prepare.primaryActionSurface, in: RoundedRectangle(cornerRadius: 12))
        }.padding(20).workoutOutline(radius: 24)
    }
}


private struct TrainingRewardToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(
                    Color.repbaseDynamic(light: Color(hex: 0x4E7461), dark: Color(hex: 0x9AC4AB))
                )
            Text(message)
                .font(.community(.footnote, weight: .semibold))
                .foregroundStyle(
                    Color.repbaseDynamic(light: RepbasePalette.espresso, dark: Color.white)
                )
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 48)
        .background(
            Color.repbaseDynamic(light: Color.white, dark: Color(hex: 0x252220)),
            in: Capsule()
        )
        .overlay {
            Capsule().strokeBorder(
                Color.repbaseDynamic(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.13)),
                lineWidth: 1
            )
        }
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
        .accessibilityAddTraits(.isStaticText)
    }
}

private extension View {
    /// The dashboard's own card.
    ///
    /// It was RepbasePalette.paper at 94%, with a white hairline over it --
    /// and paper is Color.white, flatly, at every appearance. In dark mode
    /// that drew a white card on a black page and then wrote Color.primary on
    /// it, which is white after dark: the card was legible only by its edges,
    /// and everything printed on it disappeared.
    func dashboardSurface(radius: CGFloat) -> some View {
        background(
            Color.repbaseDynamic(
                light: Color.white.opacity(0.94),
                dark: Color(hex: 0x252220)
            ),
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    Color.repbaseDynamic(
                        light: Color.white.opacity(0.78),
                        dark: Color.white.opacity(0.10)
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: RepbaseDesign.deepShadow, radius: 22, x: 0, y: 10)
    }
}
