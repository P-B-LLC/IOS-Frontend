//
//  GuidedHomeView.swift
//  IOS Frontend
//
//  Home reads as one guided day rather than a stack of equally weighted
//  widgets. Every value and destination below comes from an existing store.
//

import SwiftUI

/// What home leads with.
///
/// The personalization flow asks this outright and calls it "home screen
/// emphasis", so the honest reading is that it decides the order of the day.
nonisolated enum HomeEmphasis: String {
    case training = "Training"
    case movement = "Movement"
    case nutrition = "Nutrition"
}

struct GuidedHomeView: View {
    @Environment(SocialProfileStore.self) private var profileStore

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var emphasis = HomeEmphasis.training
#if DEBUG
    // The emphasis is set four taps into a settings flow, and simctl has no
    // tap, so the three orderings cannot otherwise be looked at.
    private let forcedEmphasis = ProcessInfo.processInfo
        .environment["REPBASE_EMPHASIS"].flatMap(HomeEmphasis.init(rawValue:))
#endif


    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuidedHomeHeader(
                        date: context.date,
                        // Steps become a chapter of their own when movement
                        // leads, and two readings of the same number on one
                        // page is one too many.
                        showsSteps: emphasis != .movement
                    )

                    GuidedHomeWeekStrip(
                        today: context.date,
                        selection: $selectedDate
                    )
                    GuidedDayFlow(
                        selectedDate: selectedDate,
                        today: context.date,
                        emphasis: emphasis
                    )


                    GuidedHomeErrors()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, RepbaseDesign.bottomBarClearance)
            }
            .scrollIndicators(.hidden)
            .minimizesBottomBarOnScroll()
            .toolbar(.hidden, for: .navigationBar)
            // Keyed on the connection: home appears before the session is
            // restored, and a bare .task would ask a store with nothing to
            // answer from and never ask again.
            .task(id: profileStore.isConnected) {
#if DEBUG
                if let forcedEmphasis {
                    emphasis = forcedEmphasis
                    return
                }
#endif
                guard let values = try? await profileStore.personalization() else {
                    return
                }
                emphasis = HomeEmphasis(rawValue: values.emphasis) ?? .training
            }

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
    var showsSteps = true

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

            if showsSteps {
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
    @Environment(CycleStore.self) private var cycles
    @Environment(\.homeTimeOfDay) private var timeOfDay

    @State private var isConfirmingClear = false

    let selectedDate: Date
    let today: Date
    var emphasis = HomeEmphasis.training

    /// The stages of the day, in the order this person asked for.
    ///
    /// Up Next and the momentum figures stay where they are: one is what is
    /// happening next regardless of what matters most, and the other is a
    /// footer. What moves is which of the three chapters leads.
    private enum Chapter: String {
        case movement = "MOVEMENT"
        case training = "TRAINING"
        case fuel = "FUEL"
        case finish = "FINISH"
    }

    private var chapters: [Chapter] {
        switch emphasis {
        case .training:
            [.training, .fuel, .finish]
        case .nutrition:
            [.fuel, .training, .finish]
        case .movement:
            // Movement is the one emphasis with no chapter of its own, so it
            // gets one rather than quietly behaving like Training. Steps move
            // out of the header and lead the day.
            [.movement, .training, .fuel, .finish]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                flowHeader
                upNextSection
            }
            ForEach(Array(chapters.enumerated()), id: \.element) { index, chapter in
                chapterView(chapter, number: index + 1)
            }
            momentumSection
        }
    }

    @ViewBuilder
    private func chapterView(_ chapter: Chapter, number: Int) -> some View {
        switch chapter {
        case .movement: movementSection(number: number)
        case .training: trainingSection(number: number)
        case .fuel: fuelSection(number: number)
        case .finish: finishSection(number: number)
        }
    }

    /// "01 · TRAINING", but the number follows where the chapter landed.
    ///
    /// Numbering them in place is the point: a page that opens on "02 · FUEL"
    /// reads as though something is missing above it.
    private func stageNumber(_ number: Int, _ chapter: Chapter) -> String {
        String(format: "%02d · %@", number, chapter.rawValue)
    }

    private func movementSection(number: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            stageLabel(stageNumber(number, .movement), color: timeOfDay.accent)
            // Explains itself when empty, which home does not normally do. The
            // reason it stays quiet elsewhere is that a card about Health is
            // noise on a page nobody opened to think about Health -- and that
            // stops being true the moment somebody asks for movement to lead.
            // A chapter with a heading and nothing under it is worse.
            StepsWidget(explainsWhenEmpty: true)
        }
        .padding(.vertical, 14)
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
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var upNextSection
: some View {
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
                .padding(.vertical, 12)
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
            .padding(.vertical, 12)
        }
    }

    private func trainingSection(number: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                stageLabel(stageNumber(number, .training), color: timeOfDay.accent)
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

            // Only without a rotation. With one running the rotation is what
            // fills the calendar, so clearing would delete days it writes
            // straight back -- the server refuses it for that reason, and a
            // button that cannot work is worse than no button.
            if cycles.activeCycle == nil, workouts.hasAnythingScheduled {
                Button {
                    isConfirmingClear = true
                } label: {
                    Label("Clear my schedule", systemImage: "calendar.badge.minus")
                        .font(.community(.caption, weight: .semibold))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
                .buttonStyle(.plain)
                .disabled(workouts.isSaving)
                .padding(.top, 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            trainingSurface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        // Asked about, unlike the destructive controls here that act on a tap:
        // this empties weeks of planning at once and cannot be undone.
        .confirmationDialog(
            "Clear everything you have planned?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear my schedule", role: .destructive) {
                Task { await workouts.clearSchedule() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Every workout you have planned is removed, past days included, so you can plan again from scratch. Workouts you have already done stay in your history.")
        }
    }

    private func fuelSection(number: Int) -> some View {
        let total = food.total(on: selectedDate)
        let goals = food.goals

        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                stageLabel(stageNumber(number, .fuel), color: fuelAccent)
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
        .padding(.vertical, 12)
        .background(
            fuelSurface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func finishSection(number: Int) -> some View {
        NavigationLink {
            PlannerView(showsBackButton: true)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    stageLabel(stageNumber(number, .finish), color: timeOfDay.secondaryText)
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
            .padding(.vertical, 14)
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
        .padding(.vertical, 13)
        .background(
            momentumSurface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func momentumMetric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.community(.title3, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text(label)
                .font(.community(size: 8, weight: .bold))
                .tracking(0.25)
                .foregroundStyle(timeOfDay.canvasSecondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var momentumDivider: some View {
        Rectangle()
            .fill(timeOfDay.canvasBorder)
            .frame(width: 1, height: 40)
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

    private var fuelAccent: Color {
        .repbaseDynamic(light: Color(hex: 0x5DAA86), dark: Color(hex: 0x84CFA9))
    }

    private var trainingSurface: Color {
        .repbaseDynamic(
            light: Color(hex: 0xE6D9D3).opacity(0.78),
            dark: Color(hex: 0x322B28)
        )
    }

    private var fuelSurface: Color {
        .repbaseDynamic(light: Color(hex: 0xF1F8F4), dark: Color(hex: 0x203029))
    }

    private var momentumSurface: Color {
        .repbaseDynamic(
            light: Color(hex: 0xE6D9D3).opacity(0.66),
            dark: Color(hex: 0x2C2927)
        )
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
