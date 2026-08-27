//
//  GuidedHomeView.swift
//  IOS Frontend
//
//  Home reads as one guided day rather than a stack of equally weighted
//  widgets. Every value and destination below comes from an existing store.
//

import SwiftUI

struct GuidedHomeView: View {
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuidedHomeHeader(date: context.date)
                    GuidedHomeWeekStrip(
                        today: context.date,
                        selection: $selectedDate
                    )
                    GuidedDayFlow(
                        selectedDate: selectedDate,
                        today: context.date
                    )

                    GuidedHomeErrors()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, RepbaseDesign.bottomBarClearance)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
        }
    }
}

// MARK: - Header

private struct GuidedHomeHeader: View {
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(ActivityStore.self) private var activity
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let date: Date

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting.uppercased())
                    .font(.community(.caption2, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(timeOfDay.accent)

                Text(firstName)
                    .font(.community(.largeTitle, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(timeOfDay.canvasPrimaryText)

                Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.community(.footnote))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(stepCount)
                    .font(.community(.title2, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)

                Text(stepCaption)
                    .font(.community(.caption2, weight: .bold))
                    .tracking(0.35)
                    .foregroundStyle(timeOfDay.canvasSecondaryText)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(timeOfDay.canvasBorder)
                        Capsule()
                            .fill(timeOfDay.accent)
                            .frame(width: proxy.size.width * stepProgress)
                    }
                }
                .frame(width: 88, height: 3)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(stepAccessibilityLabel)
        }
        .frame(minHeight: 82)
    }

    private var firstName: String {
        guard case .signedIn(let user) = authentication.phase else { return "Your day" }
        let given = user.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return given.isEmpty ? user.username : given
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var stepCount: String {
        activity.stepsToday?.formatted() ?? "—"
    }

    private var stepProgress: Double {
        guard let steps = activity.stepsToday, activity.stepGoal > 0 else { return 0 }
        return min(max(Double(steps) / Double(activity.stepGoal), 0), 1)
    }

    private var stepCaption: String {
        guard activity.stepsToday != nil else { return "STEPS · NOT REPORTED" }
        return "STEPS · \(stepProgress.formatted(.percent.precision(.fractionLength(0))))"
    }

    private var stepAccessibilityLabel: String {
        guard let steps = activity.stepsToday else { return "Steps have not been reported today" }
        return "\(steps) steps today, \(stepProgress.formatted(.percent.precision(.fractionLength(0)))) of the daily goal"
    }
}

// MARK: - Week selector

private struct GuidedHomeWeekStrip: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(WorkoutStore.self) private var workouts
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let today: Date
    @Binding var selection: Date

    var body: some View {
        HStack(spacing: 3) {
            ForEach(weekDates, id: \.self) { day in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selection = day
                    }
                    planner.select(day)
                } label: {
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.narrow)).uppercased())
                            .font(.community(.caption2, weight: .bold))
                        Text(day.formatted(.dateTime.day()))
                            .font(.community(.subheadline, weight: .bold))

                        Circle()
                            .fill(dayHasContent(day) ? dotColor(for: day) : .clear)
                            .frame(width: 3, height: 3)
                    }
                    .foregroundStyle(isSelected(day) ? Color.white : timeOfDay.canvasPrimaryText)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected(day) ? timeOfDay.accent : Color.clear)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(isSelected(day) ? [.isSelected] : [])
            }
        }
        .padding(5)
        .background(
            timeOfDay.surfaceRaised,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(timeOfDay.border, lineWidth: 1)
        }
        .shadow(color: timeOfDay.shadow.opacity(0.55), radius: 14, x: 0, y: 5)
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selection)
        else { return [selection] }
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    private func isSelected(_ day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: selection)
    }

    private func dayHasContent(_ day: Date) -> Bool {
        let weekday = Weekday(calendarWeekday: Calendar.current.component(.weekday, from: day))
        return planner.hasEntries(on: day)
            || weekday.map { !workouts.workouts(on: $0).isEmpty } == true
    }

    private func dotColor(for day: Date) -> Color {
        isSelected(day) ? Color.white : timeOfDay.accent
    }
}

// MARK: - Connected daily flow

private struct GuidedDayFlow: View {
    @Environment(WorkoutStore.self) private var workouts
    @Environment(PlannerStore.self) private var planner
    @Environment(FoodTrackingStore.self) private var food
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let selectedDate: Date
    let today: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            flowHeader
            upNextSection
            trainingSection
            fuelSection
            finishSection
            momentumSection
        }
        .background(timeOfDay.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(timeOfDay.border, lineWidth: 1)
        }
        .shadow(color: timeOfDay.shadow.opacity(0.85), radius: 22, x: 0, y: 10)
    }

    private var flowHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("YOUR DAY")
                    .font(.community(.caption2, weight: .bold))
                    .tracking(0.55)
                    .foregroundStyle(timeOfDay.accent)
                Text("Follow what matters.")
                    .font(.community(.title3, weight: .bold))
                    .foregroundStyle(timeOfDay.primaryText)
            }
            Spacer()
            Text(selectedDate.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(.community(.caption, weight: .bold))
                .foregroundStyle(timeOfDay.secondaryText)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var upNextSection: some View {
        if let entry = nextEntry {
            NavigationLink {
                PlannerView(showsBackButton: true)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nextEntryEyebrow(entry))
                            .font(.community(.caption2, weight: .bold))
                            .tracking(0.35)
                            .foregroundStyle(timeOfDay.accent)
                        Text(entry.title)
                            .font(.community(.headline))
                            .foregroundStyle(timeOfDay.primaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    actionLabel("Schedule")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(upNextBackground)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UP NEXT")
                        .font(.community(.caption2, weight: .bold))
                        .foregroundStyle(timeOfDay.accent)
                    Text("Your schedule is clear")
                        .font(.community(.headline))
                        .foregroundStyle(timeOfDay.primaryText)
                }
                Spacer()
                NavigationLink {
                    PlannerView(showsBackButton: true)
                } label: {
                    actionLabel("Plan")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(upNextBackground)
        }
    }

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                stageLabel("01 · TRAINING", color: timeOfDay.accent)
                Spacer()
                Text(workout?.type.title.uppercased() ?? "WORKOUT")
                    .font(.community(.caption2, weight: .bold))
                    .foregroundStyle(timeOfDay.secondaryText)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout?.name ?? "Plan your workout")
                        .font(.community(.title2, weight: .bold))
                        .foregroundStyle(timeOfDay.primaryText)
                        .lineLimit(1)
                    Text(workoutMetadata)
                        .font(.community(.footnote))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
                Spacer(minLength: 8)

                NavigationLink {
                    workoutDestination
                } label: {
                    HStack(spacing: 7) {
                        Text(workout == nil ? "Plan" : (activeSession == nil ? "Start" : "Continue"))
                        Image(systemName: "arrow.right")
                    }
                    .font(.community(.subheadline, weight: .bold))
                    .foregroundStyle(timeOfDay.onPrimaryAction)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(
                        timeOfDay.primaryActionSurface,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            Text(workoutDetail)
                .font(.community(.caption))
                .foregroundStyle(timeOfDay.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(trainingBackground)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }

    private var fuelSection: some View {
        let total = food.total(on: selectedDate)
        let goals = food.goals

        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                stageLabel("02 · FUEL", color: fuelAccent)
                Spacer()
                NavigationLink {
                    FoodTrackingView()
                } label: {
                    actionLabel("Log food", color: fuelAccent)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(total.calories.nutritionText)
                    .font(.community(.title2, weight: .bold))
                    .foregroundStyle(timeOfDay.primaryText)
                Text("of \(goals.calories.nutritionText) kcal")
                    .font(.community(.footnote))
                    .foregroundStyle(timeOfDay.secondaryText)
            }

            HStack(spacing: 10) {
                GuidedMacroMetric(
                    label: "PROTEIN",
                    value: total.proteinGrams,
                    goal: goals.proteinGrams,
                    color: Color(hex: 0xF56B33)
                )
                GuidedMacroMetric(
                    label: "CARBS",
                    value: total.carbohydrateGrams,
                    goal: goals.carbohydrateGrams,
                    color: Color(hex: 0x29B8BA)
                )
                GuidedMacroMetric(
                    label: "FAT",
                    value: total.fatGrams,
                    goal: goals.fatGrams,
                    color: Color(hex: 0xB847AD)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(fuelBackground)
    }

    private var finishSection: some View {
        NavigationLink {
            PlannerView(showsBackButton: true)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    stageLabel("03 · FINISH", color: timeOfDay.secondaryText)
                    Text(taskSummary)
                        .font(.community(.headline))
                        .foregroundStyle(timeOfDay.primaryText)
                    Text(taskDetail)
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                actionLabel("Open")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var momentumSection: some View {
        HStack(spacing: 0) {
            momentumMetric(
                value: workouts.trainingStats.completedThisWeek.formatted(),
                label: "WORKOUTS"
            )
            momentumDivider
            momentumMetric(
                value: workouts.trainingStats.currentStreakWeeks.formatted(),
                label: "WEEK STREAK"
            )
            momentumDivider
            momentumMetric(
                value: weeklyProgress.formatted(.percent.precision(.fractionLength(0))),
                label: "WEEKLY GOAL"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RepbasePalette.night)
    }

    private func momentumMetric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.community(.title3, weight: .bold))
            Text(label)
                .font(.community(size: 8, weight: .bold))
                .tracking(0.25)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var momentumDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1, height: 48)
    }

    private func stageLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.community(.caption2, weight: .bold))
            .tracking(0.45)
            .foregroundStyle(color)
    }

    private func actionLabel(_ text: String, color: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "arrow.right")
        }
        .font(.community(.caption, weight: .semibold))
        .foregroundStyle(color ?? timeOfDay.accent)
    }

    @ViewBuilder
    private var workoutDestination: some View {
        if let weekday {
            DayWorkoutView(day: weekday)
        } else {
            WorkoutsView()
        }
    }

    private var isToday: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: today)
    }

    private var weekday: Weekday? {
        Weekday(calendarWeekday: Calendar.current.component(.weekday, from: selectedDate))
    }

    private var workout: Workout? {
        guard let weekday else { return nil }
        return workouts.workout(on: weekday)
    }

    private var activeSession: ActiveWorkoutSession? {
        isToday ? workouts.activeSession : nil
    }

    private var workoutMetadata: String {
        guard let workout else { return "Choose a plan or build something new" }
        let exercises = workout.exercises.count
        return "\(exercises) \(exercises == 1 ? "exercise" : "exercises") · \(workout.totalSets) target sets"
    }

    private var workoutDetail: String {
        if let activeSession {
            return "Session in progress · \(activeSession.workoutName)"
        }
        guard let workout else { return "Your training plan for this day is open" }
        if let first = workout.exercises.first {
            let remaining = max(workout.exercises.count - 1, 0)
            return remaining == 0 ? first.name : "\(first.name) and \(remaining) more"
        }
        return workout.type.title
    }

    private var nextEntry: PlannerEntry? {
        let overdue = isToday ? planner.pastDue.filter { !$0.isComplete } : []
        let onDay = planner.entries(on: selectedDate).filter { !$0.isComplete || !$0.isCompletable }
        var seen: Set<PlannerEntry.ID> = []
        return (overdue + onDay)
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.time ?? "99:99:99") < ($1.time ?? "99:99:99") }
            .first
    }

    private func nextEntryEyebrow(_ entry: PlannerEntry) -> String {
        guard let time = entry.displayTime else { return "UP NEXT" }
        return "UP NEXT · \(time)"
    }

    private var remainingTasks: [PlannerEntry] {
        let overdue = isToday
            ? planner.pastDue.filter { $0.isCompletable && !$0.isComplete }
            : []
        let onDay = planner.entries(on: selectedDate)
            .filter { $0.isCompletable && !$0.isComplete }
        var seen: Set<PlannerEntry.ID> = []
        return (overdue + onDay).filter { seen.insert($0.id).inserted }
    }

    private var taskSummary: String {
        let count = remainingTasks.count
        return count == 0 ? "Everything is done" : "\(count) task\(count == 1 ? "" : "s") still to do"
    }

    private var taskDetail: String {
        guard let task = remainingTasks.first else { return "Nothing else needs your attention" }
        if let time = task.displayTime { return "\(task.title) · due by \(time)" }
        return task.title
    }

    private var weeklyProgress: Double {
        let stats = workouts.trainingStats
        guard stats.weeklyGoal > 0 else { return 0 }
        return min(max(Double(stats.completedThisWeek) / Double(stats.weeklyGoal), 0), 1)
    }

    private var upNextBackground: Color {
        timeOfDay.usesDarkAppearance ? Color(hex: 0x2E211D) : Color(hex: 0xFBEDE5)
    }

    private var trainingBackground: Color {
        timeOfDay.usesDarkAppearance ? Color(hex: 0x241D1A) : Color(hex: 0xFFF9F4)
    }

    private var fuelBackground: Color {
        timeOfDay.usesDarkAppearance ? Color(hex: 0x18241F) : Color(hex: 0xEDF6F1)
    }

    private var fuelAccent: Color {
        timeOfDay.usesDarkAppearance ? Color(hex: 0x84CFA9) : Color(hex: 0x5DAA86)
    }
}

private struct GuidedMacroMetric: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let label: String
    let value: Decimal
    let goal: Decimal
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.community(size: 8, weight: .bold))
                .foregroundStyle(timeOfDay.secondaryText)
            Text("\(value.nutritionText) / \(goal.nutritionText)g")
                .font(.community(.caption, weight: .semibold))
                .foregroundStyle(timeOfDay.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(timeOfDay.canvasBorder)
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(max(value.nutritionDouble / goal.nutritionDouble, 0), 1)
    }
}

// MARK: - Store errors

private struct GuidedHomeErrors: View {
    @Environment(WorkoutStore.self) private var workouts
    @Environment(PlannerStore.self) private var planner
    @Environment(FoodTrackingStore.self) private var food
    @Environment(ActivityStore.self) private var activity

    var body: some View {
        VStack(spacing: 8) {
            if let error = workouts.persistenceError {
                errorLine(error) { workouts.retryPersistence() }
            }
            if let error = planner.persistenceError {
                errorLine(error) { planner.retry() }
            }
            if let error = food.errorMessage {
                errorLine(error, retry: nil)
            }
            if let error = activity.persistenceError {
                errorLine(error, retry: nil)
            }
        }
    }

    private func errorLine(_ message: String, retry: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .font(.community(.footnote))
                .lineLimit(2)
            Spacer(minLength: 4)
            if let retry {
                Button("Retry", action: retry)
                    .font(.community(.footnote, weight: .bold))
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
