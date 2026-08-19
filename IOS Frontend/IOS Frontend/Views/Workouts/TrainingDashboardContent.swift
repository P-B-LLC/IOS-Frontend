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
    @Binding var isSharingWorkout: Bool

    private var phase: WorkoutVisualPhase {
        store.activeSession == nil ? .prepare : .focus
    }

    private var metrics: TrainingDashboardMetrics {
        TrainingDashboardMetrics(
            sessions: store.dashboardSessions,
            plannedWorkoutCount: store.currentWeekWorkouts.count
        )
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
                    intro
                    focusCard
                    momentumSection
                    shareButton
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 10)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR TRAINING")
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(phase.secondaryText)
            Text("Build momentum.")
                .font(.title.weight(.bold))
                .tracking(-0.6)
                .foregroundStyle(phase.primaryText)
            Text("Today’s plan, your weekly goal, and the progress behind it.")
                .font(.footnote)
                .foregroundStyle(phase.secondaryText)
        }
    }

    private var workoutPlanCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Workout plan").font(.headline)
                Spacer()
                Text("\(store.currentWeekWorkouts.count) planned")
                    .font(.footnote)
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
                            isSessionActive: store.activeSession?.day == day
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .dashboardSurface(radius: 22)
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
                    goal: metrics.weeklyGoal
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
                    completed: metrics.completedThisWeek,
                    goal: metrics.weeklyGoal
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var momentumSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Momentum").font(.title2.weight(.bold))
                Text("Your consistency at a glance")
                    .font(.footnote)
                    .foregroundStyle(phase.secondaryText)
            }

            totalsCard
            trendCard
            milestoneCard

            if store.isLoadingDashboardSessions && store.dashboardSessions.isEmpty {
                ProgressView("Loading progress from Repbase...")
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var totalsCard: some View {
        HStack(spacing: 0) {
            metric(
                eyebrow: "TOTAL WORKOUTS",
                value: "\(metrics.totalWorkouts)",
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
        .dashboardSurface(radius: 21)
    }

    private func metric(eyebrow: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(phase.secondaryText)
            Text(value)
                .font(.title.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(detail)
                .font(.caption.weight(.semibold))
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
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(phase.secondaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(metrics.trendPercentText).font(.title2.weight(.bold))
                        Text("vs last week")
                            .font(.caption)
                            .foregroundStyle(phase.secondaryText)
                    }
                }
                Spacer()
                Label(metrics.trendLabel, systemImage: metrics.trendSymbol)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RepbasePalette.oatmeal, in: Capsule())
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
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(index == 5 ? RepbaseDesign.warning : phase.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Week \(index + 1), \(count) completed workouts")
                }
            }
        }
        .padding(18)
        .dashboardSurface(radius: 22)
    }

    private var milestoneCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("NEXT MILESTONE")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(phase.secondaryText)
                Text(metrics.milestoneTitle)
                    .font(.callout.weight(.semibold))
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 7) {
                ProgressView(value: metrics.milestoneProgress)
                    .tint(RepbaseDesign.ink)
                    .frame(width: 78)
                Text("\(metrics.totalWorkouts) / \(metrics.nextMilestone)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(phase.secondaryText)
            }
        }
        .padding(16)
        .background(RepbasePalette.oatmeal, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    private var shareButton: some View {
        Button {
            isSharingWorkout = true
        } label: {
            Label("Share a workout", systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .repbaseControlSurface(cornerRadius: 15)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Color.orange)
            Button("Retry") { store.retryPersistence() }
                .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private func focusDescription(for day: Weekday) -> String {
        guard let workout = store.workout(on: day) else {
            return "Add a name, exercises, and target sets."
        }
        return "\(workout.exercises.count) exercises  ·  \(workout.totalSets) target sets"
    }
}

private struct DashboardDayItem: View {
    let day: Weekday
    let workouts: [Workout]
    let isToday: Bool
    let isSessionActive: Bool

    private var isPlanned: Bool { !workouts.isEmpty }

    var body: some View {
        VStack(spacing: 6) {
            Text(day.shortName.uppercased())
                .font(.system(size: 9, weight: isToday ? .bold : .semibold))
                .foregroundStyle(isToday ? RepbaseDesign.warning : Color.secondary)

            ZStack {
                Circle()
                    .fill(isToday ? RepbaseDesign.warning : isPlanned ? RepbaseDesign.ink : RepbasePalette.oatmeal)
                Image(systemName: isSessionActive ? "bolt.fill" : isPlanned ? "minus" : "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isPlanned || isSessionActive ? RepbasePalette.paper : Color.secondary)
            }
            .frame(width: 34, height: 34)
            .overlay(alignment: .topTrailing) {
                if workouts.count > 1 {
                    Text("\(workouts.count)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(RepbaseDesign.warning, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }

            Text(workouts.first?.name ?? " ")
                .font(.system(size: 10, weight: isToday ? .semibold : .regular))
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
        return "\(day.fullName), \(workouts.map(\.name).joined(separator: ", "))"
    }
}

private struct WorkoutDashboardHero: View {
    let eyebrow: String
    let title: String
    let detail: String
    let completed: Int
    let goal: Int

    private var remaining: Int { max(goal - completed, 0) }
    private var progress: Double { min(Double(completed) / Double(max(goal, 1)), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow)
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(Color.secondary)
                    Text(title)
                        .font(.title2.weight(.bold))
                        .tracking(-0.4)
                        .foregroundStyle(RepbaseDesign.ink)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Label("Start", systemImage: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RepbasePalette.paper)
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .background(RepbaseDesign.ink, in: Capsule())
                    .shadow(color: Color.black.opacity(0.20), radius: 10, x: 0, y: 5)
            }

            DashboardDumbbell()
                .frame(maxWidth: .infinity)
                .frame(height: 112)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEEKLY GOAL")
                            .font(.caption2.weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(.secondary)
                        Text("\(completed) of \(goal) workouts")
                            .font(.headline)
                            .foregroundStyle(RepbaseDesign.ink)
                    }
                    Spacer()
                    Text(remaining == 0 ? "Goal met" : "\(remaining) to go")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(RepbasePalette.paper, in: Capsule())
                }
                ProgressView(value: progress).tint(RepbaseDesign.warning)
            }
            .padding(14)
            .background(RepbasePalette.oatmeal, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .padding(18)
        .dashboardSurface(radius: 24)
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

private struct TrainingDashboardMetrics {
    let sessions: [PostableSession]
    let plannedWorkoutCount: Int
    private let calendar = Calendar.current

    /// One workout trained on one day, however many sessions that took.
    ///
    /// Everything below counts these rather than sessions. A session is
    /// created by tapping Start, so counting sessions meant starting Tuesday's
    /// workout six times read as six workouts and a met weekly goal — which is
    /// what it did. Starting a day again, to redo a set or after discarding by
    /// accident, is a normal thing to do and must not inflate the record of
    /// what was trained.
    private struct TrainingDay: Hashable {
        let workoutName: String
        let day: Date
    }

    /// The distinct days trained, newest first.
    private var trainingDays: [TrainingDay] {
        var seen: Set<TrainingDay> = []
        var result: [TrainingDay] = []
        for session in sessions.sorted(by: { $0.performedAt > $1.performedAt }) {
            let entry = TrainingDay(
                workoutName: session.workoutName,
                day: calendar.startOfDay(for: session.performedAt)
            )
            if seen.insert(entry).inserted {
                result.append(entry)
            }
        }
        return result
    }

    var totalWorkouts: Int { trainingDays.count }
    var weeklyGoal: Int { max(plannedWorkoutCount, 1) }
    var completedThisWeek: Int { count(in: .weekOfYear) }
    var completedThisMonth: Int { count(in: .month) }
    var monthDetail: String { completedThisMonth == 0 ? "None this month" : "+\(completedThisMonth) this month" }

    private func count(in component: Calendar.Component) -> Int {
        trainingDays.filter {
            calendar.isDate($0.day, equalTo: Date(), toGranularity: component)
        }.count
    }

    private var activeWeeks: Set<Date> {
        Set(trainingDays.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.day)?.start })
    }

    var currentStreak: Int {
        guard var cursor = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        if !activeWeeks.contains(cursor), let prior = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) {
            cursor = prior
        }
        var result = 0
        while activeWeeks.contains(cursor) {
            result += 1
            guard let prior = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prior
        }
        return result
    }

    var bestStreak: Int {
        let weeks = activeWeeks.sorted()
        guard !weeks.isEmpty else { return 0 }
        var best = 1
        var run = 1
        for (earlier, later) in zip(weeks, weeks.dropFirst()) {
            if calendar.dateComponents([.weekOfYear], from: earlier, to: later).weekOfYear == 1 {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }

    var currentStreakText: String { "\(currentStreak) \(currentStreak == 1 ? "week" : "weeks")" }
    var bestStreakText: String { "\(bestStreak) \(bestStreak == 1 ? "week" : "weeks")" }

    var sixWeekCounts: [Int] {
        guard let current = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return Array(repeating: 0, count: 6)
        }
        return (0..<6).reversed().map { offset in
            guard let week = calendar.date(byAdding: .weekOfYear, value: -offset, to: current) else { return 0 }
            return trainingDays.filter {
                calendar.dateInterval(of: .weekOfYear, for: $0.day)?.start == week
            }.count
        }
    }

    private var trendPercent: Int {
        let prior = sixWeekCounts[4]
        let current = sixWeekCounts[5]
        guard prior > 0 else { return current > 0 ? 100 : 0 }
        return Int(((Double(current - prior) / Double(prior)) * 100).rounded())
    }

    var trendPercentText: String { String(format: "%+d%%", trendPercent) }
    var trendLabel: String { trendPercent > 0 ? "Improving" : trendPercent < 0 ? "Easing" : "Steady" }
    var trendSymbol: String { trendPercent > 0 ? "arrow.up.right" : trendPercent < 0 ? "arrow.down.right" : "arrow.right" }

    func barHeight(for count: Int) -> CGFloat {
        let maximum = max(sixWeekCounts.max() ?? 0, 1)
        return max(12, 82 * CGFloat(count) / CGFloat(maximum))
    }

    var nextMilestone: Int { ((totalWorkouts / 10) + 1) * 10 }
    var workoutsToMilestone: Int { nextMilestone - totalWorkouts }
    var milestoneTitle: String { "\(workoutsToMilestone) workout\(workoutsToMilestone == 1 ? "" : "s") to reach \(nextMilestone)" }
    var milestoneProgress: Double {
        let start = max(nextMilestone - 10, 0)
        return Double(totalWorkouts - start) / Double(max(nextMilestone - start, 1))
    }
}

private extension View {
    func dashboardSurface(radius: CGFloat) -> some View {
        background(RepbasePalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
            }
            .shadow(color: RepbaseDesign.deepShadow, radius: 22, x: 0, y: 10)
    }
}

