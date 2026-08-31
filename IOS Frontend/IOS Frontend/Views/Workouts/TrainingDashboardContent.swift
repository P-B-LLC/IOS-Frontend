//
//  TrainingDashboardContent.swift
//  IOS Frontend
//
//  The approved soft-luxury training dashboard. Existing navigation and
//  actions are preserved; every statistic is derived from API-owned records.
//

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
                if let persistenceError = store.persistenceError {
                    errorCard(persistenceError)
                }

                if store.isLoading {
                    ProgressView("Loading this week from Repbase...")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                        .workoutCard()
                } else {
                    workoutPlanCard
                    StepsWidget(explainsWhenEmpty: true, compact: true)
                    focusCard
                    momentumSection
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 10)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .minimizesBottomBarOnScroll()
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
            HStack {
                Text("Workout plan").font(.community(.headline))
                Spacer()
                Text("\(store.currentWeekWorkouts.count) planned")
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
                            workouts: store.workouts(on: day),
                            isToday: store.today == day,
                            isSessionActive: store.activeSession?.day == day,
                            isCompleted: isCompleted(day) && hiddenCompletedDay != day
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

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
                    Text(cycles.activeCycle?.positionText ?? "Repeating split")
                        .font(.community(.subheadline, weight: .semibold))
                        .foregroundStyle(phase.primaryText)
                    Text(cycleDetail)
                        .font(.community(.caption))
                        .foregroundStyle(phase.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.community(.caption, weight: .semibold))
                    .foregroundStyle(phase.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cycleDetail: String {
        guard let cycle = cycles.activeCycle else {
            return "Train on a cycle, not a weekly plan"
        }
        return "\(cycle.currentWorkoutName) today"
    }

    @ViewBuilder
    private var focusCard: some View {
        if let session = store.activeSession {
            NavigationLink {
                DayWorkoutView(day: session.day)
            } label: {
                WorkoutDashboardHero(
                    eyebrow: "SESSION IN PROGRESS",
                    title: session.workoutName,
                    detail: "\(session.loggedSetCount) of \(session.totalSetCount) sets logged",
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
                WorkoutDashboardHero(
                    eyebrow: "TODAY",
                    title: store.workout(on: day)?.name ?? "Plan today’s workout",
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
                Text(rewardIsVisible ? "Momentum gained." : "Momentum")
                    .font(.community(.title2, weight: .bold))
                    .contentTransition(.opacity)
                Text(rewardIsVisible ? "That session moved the whole week forward." : "Your consistency at a glance")
                    .font(.community(.footnote))
                    .foregroundStyle(phase.secondaryText)
            }

            totalsCard
            trendCard
            milestoneCard

            if store.isLoadingDashboardSessions && store.dashboardSessions.isEmpty {
                ProgressView("Loading progress from Repbase...")
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
                detail: "Best: \(metrics.bestStreakText)",
                color: phase.secondaryText
            )
        }
        .padding(.vertical, 17)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func metric(eyebrow: String, value: String, detail: String, color: Color) -> some View {
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
                    Text("TRAINING VOLUME")
                        .font(.community(.caption2, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(phase.secondaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(metrics.trendPercentText).font(.community(.title2, weight: .bold))
                        Text("vs last week")
                            .font(.community(.caption))
                            .foregroundStyle(phase.secondaryText)
                    }
                }
                Spacer()
                Label(metrics.trendLabel, systemImage: metrics.trendSymbol)
                    .font(.community(.caption2, weight: .semibold))
                    .foregroundStyle(phase.secondaryText)
            }

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(metrics.sixWeekCounts.enumerated()), id: \.offset) { index, count in
                    VStack(spacing: 7) {
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(RepbasePalette.oatmeal.opacity(0.72))
                                .frame(height: 86)
                            Capsule()
                                .fill(index == 5 ? RepbaseDesign.warning : RepbaseDesign.ink)
                                .frame(height: metrics.barHeight(for: count))
                        }
                        Text(index == 5 ? "NOW" : "W\(index + 1)")
                            .font(.community(size: 9, weight: .bold))
                            .foregroundStyle(index == 5 ? RepbaseDesign.warning : phase.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Week \(index + 1), \(count) completed workouts")
                }
            }
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
                    .tint(RepbaseDesign.ink)
                    .frame(width: 78)
                Text("\(metrics.totalWorkouts) / \(metrics.nextMilestone)")
                    .font(.community(.caption2, weight: .semibold))
                    .foregroundStyle(phase.secondaryText)
            }
        }
        .padding(.vertical, 14)
    }

    private func isCompleted(_ day: Weekday) -> Bool {
        guard let workout = store.workout(on: day) else { return false }
        return store.isCompleted(
            workoutName: workout.name,
            on: store.workoutDate(for: day)
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
                rewardToast = "\(reward.workoutName) complete · goal moved forward"
            }
            RepbaseCelebrations.show(.workoutLogged)

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
            return "Add a name, exercises, and target sets."
        }
        let exerciseLabel = workout.exercises.count == 1 ? "exercise" : "exercises"
        let setLabel = workout.totalSets == 1 ? "target set" : "target sets"
        return "\(workout.exercises.count) \(exerciseLabel)  ·  \(workout.totalSets) \(setLabel)"
    }
}

private struct DashboardDayItem: View {
    let day: Weekday
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

            ZStack {
                Circle()
                    .fill(dayMarkerColor)
                Image(systemName: dayMarkerSymbol)
                    .font(.community(size: 16, weight: .bold))
                    .foregroundStyle(isPlanned || isSessionActive || isCompleted ? RepbaseDesign.onInk : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 34, height: 34)
            .scaleEffect(isCompleted ? 1.06 : 1)
            .animation(.spring(response: 0.48, dampingFraction: 0.68), value: isCompleted)
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

            Text(workouts.first?.name ?? " ")
                .font(.community(size: 10, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? RepbaseDesign.warning : RepbaseDesign.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .frame(height: 25, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(RepbasePalette.oatmeal.opacity(0.72))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard isPlanned else { return "\(day.fullName), add workout" }
        let completion = isCompleted ? ", completed" : ""
        return "\(day.fullName), \(workouts.map(\.name).joined(separator: ", "))\(completion)"
    }

    private var dayMarkerSymbol: String {
        if isCompleted { return "checkmark" }
        if isSessionActive { return "bolt.fill" }
        return isPlanned ? "minus" : "plus"
    }

    private var dayMarkerColor: Color {
        if isCompleted {
            return .repbaseDynamic(light: Color(hex: 0x5F806F), dark: Color(hex: 0x7BA890))
        }
        if isToday { return RepbaseDesign.warning }
        return isPlanned ? RepbaseDesign.ink : RepbasePalette.oatmeal
    }
}

private struct WorkoutDashboardHero: View {
    let eyebrow: String
    let title: String
    let detail: String
    let completed: Int
    let goal: Int
    let workoutType: WorkoutType
    /// Whether the day this card points at has already been trained, so the
    /// pill can say what tapping it does rather than always saying Start.
    var isDayComplete = false
    var celebratesCompletion = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheenTravel: CGFloat = -1.2

    private var remaining: Int { max(goal - completed, 0) }

    /// What the chip says.
    ///
    /// It said "Goal met" whenever nothing was outstanding, and having no
    /// goal counts as nothing outstanding -- so an account that had never set
    /// one was congratulated for a week it had not trained in. Nought
    /// remaining against nought asked for is not an achievement.
    private var goalSummary: String {
        guard goal > 0 else { return "No weekly goal" }
        return remaining == 0 ? "Goal met" : "\(remaining) to go"
    }

    private var progress: Double { min(Double(completed) / Double(max(goal, 1)), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(eyebrow)  ·  \(workoutType.title.uppercased())")
                        .font(.community(.caption2, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color.secondary)
                    Text(title)
                        .font(.community(.title2, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(RepbaseDesign.ink)
                    Text(detail)
                        .font(.community(.footnote))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Label(
                    isDayComplete ? "View" : "Start",
                    systemImage: isDayComplete ? "checkmark" : "play.fill"
                )
                    .font(.community(.footnote, weight: .semibold))
                    .foregroundStyle(RepbaseDesign.onInk)
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .background(RepbaseDesign.ink, in: Capsule())
                    .shadow(color: Color.black.opacity(0.20), radius: 10, x: 0, y: 5)
            }

            HStack(spacing: 14) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(RepbaseDesign.accent)
                    .frame(width: 68, height: 68)
                    .background(
                        Color.repbaseDynamic(
                            light: Color.white.opacity(0.78),
                            dark: Color.white.opacity(0.08)
                        ),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(workoutTypePrompt)
                        .font(.community(.subheadline, weight: .semibold))
                    Text(detail)
                        .font(.community(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.community(.subheadline, weight: .semibold))
                    .foregroundStyle(RepbaseDesign.accent)
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: celebratesCompletion
                        ? [
                            Color.repbaseDynamic(light: Color(hex: 0xE5F1EA), dark: Color(hex: 0x213128)),
                            Color.repbaseDynamic(light: Color(hex: 0xF4E5DA), dark: Color(hex: 0x38251F))
                        ]
                        : [RepbaseDesign.accent.opacity(0.10), RepbaseDesign.accent.opacity(0.10)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                if celebratesCompletion && !reduceMotion {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.40), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.42)
                        .rotationEffect(.degrees(-14))
                        .offset(x: geometry.size.width * sheenTravel)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .allowsHitTesting(false)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEEKLY GOAL")
                            .font(.community(.caption2, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(.secondary)
                        Text("\(completed) of \(goal) workouts")
                            .font(.community(.headline))
                            .foregroundStyle(RepbaseDesign.ink)
                    }
                    Spacer()
                    Text(goalSummary)
                        .font(.community(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Color.repbaseDynamic(light: Color.white, dark: Color(hex: 0x3A3634)),
                            in: Capsule()
                        )
                }
                ProgressView(value: progress)
                    .tint(celebratesCompletion ? RepbasePalette.sage : RepbaseDesign.warning)
                    .animation(.spring(response: 0.72, dampingFraction: 0.82), value: progress)
            }
            .padding(14)
            .background(RepbasePalette.oatmeal, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .padding(18)
        .dashboardSurface(radius: 24)
        .scaleEffect(celebratesCompletion && !reduceMotion ? 1.008 : 1)
        .animation(.spring(response: 0.55, dampingFraction: 0.76), value: celebratesCompletion)
        .onChange(of: celebratesCompletion) { _, isCelebrating in
            guard isCelebrating, !reduceMotion else { return }
            sheenTravel = -1.2
            withAnimation(.easeInOut(duration: 0.72)) {
                sheenTravel = 2.5
            }
        }
    }

    private var workoutTypePrompt: String {
        workoutType.sessionTitle
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

private struct DashboardDumbbell: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x0D0D0E), Color(hex: 0x404245), Color(hex: 0x09090A)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 178, height: 16)
            HStack(spacing: 132) { weight; weight }
        }
        .shadow(color: Color.black.opacity(0.26), radius: 12, x: 0, y: 10)
        .overlay(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(0.13))
                .frame(width: 240, height: 16)
                .blur(radius: 8)
                .offset(y: 16)
        }
    }

    private var weight: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x3B3D40), Color(hex: 0x151617), Color(hex: 0x040405)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 38
                    )
                )
                .frame(width: 76, height: 76)
            Circle().stroke(Color.white.opacity(0.28), lineWidth: 2).frame(width: 54, height: 54)
            Circle().fill(Color(hex: 0x080809)).frame(width: 18, height: 18)
            Circle().fill(Color(hex: 0x8C969C)).frame(width: 8, height: 8)
        }
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
