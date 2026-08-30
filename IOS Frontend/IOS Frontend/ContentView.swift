//
//  ContentView.swift
//  IOS Frontend
//
//  Home is a command center, not a stack of dashboard widgets. Every section
//  below reads from an existing store and routes into an existing feature.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        GuidedHomeView()
    }
}

// MARK: - Header

private struct HomeCommandHeader: View {
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let date: Date

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HOME")
                    .font(.community(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(timeOfDay.commandAccent)

                Text("\(greeting), \(firstName)")
                    .font(.community(size: 30, weight: .bold))
                    .tracking(-0.65)
                    .foregroundStyle(timeOfDay.canvasPrimaryText)

                Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.community(size: 13, weight: .medium))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }

            Spacer(minLength: 12)
            accountMenu
        }
        .frame(minHeight: 54)
    }

    private var accountMenu: some View {
        Menu {
            if case .signedIn(let user) = authentication.phase {
                Text(user.displayName)
                Text("@\(user.username)")
            }
            Divider()
            Button("Refresh Workouts", systemImage: "arrow.clockwise") {
                workoutStore.retryPersistence()
            }
            Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                Task { await authentication.signOut() }
            }
        } label: {
            Text(initials)
                .font(.community(.subheadline, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(timeOfDay.commandAccent, in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.65), lineWidth: 1)
                }
        }
        .disabled(authentication.isWorking)
        .accessibilityLabel("Account")
    }

    /// The name the account actually holds, not the first word of the
    /// display name. Splitting guessed wrong for anyone whose first name has
    /// a space in it, and the authenticated user carries the real field.
    private var firstName: String {
        guard case .signedIn(let user) = authentication.phase else { return "there" }
        let given = user.firstName.trimmingCharacters(in: .whitespaces)
        return given.isEmpty ? user.username : given
    }

    private var initials: String {
        guard case .signedIn(let user) = authentication.phase else { return "R" }
        // Built from the two real name fields for the same reason.
        let value = [user.firstName, user.lastName]
            .compactMap { $0.trimmingCharacters(in: .whitespaces).first }
            .map(String.init)
            .joined()
        return value.isEmpty ? String(user.username.prefix(2)).uppercased() : value.uppercased()
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
}

// MARK: - Week

private struct HomeWeekStrip: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(WorkoutStore.self) private var workouts
    @Environment(\.homeTimeOfDay) private var timeOfDay

    /// The real today, so it stays marked even while another day is read.
    let today: Date
    @Binding var selection: Date

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekDates, id: \.self) { day in
                // A button, not a link. Tapping a date used to push the
                // calendar, which hides its navigation bar and so left no way
                // back to Home; and leaving Home to find out what is on
                // Thursday is the opposite of what a command centre is for.
                Button {
                    selection = day
                    // Kept in step, so opening the calendar next lands on the
                    // same day rather than on whatever was last selected there.
                    planner.select(day)
                } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.community(size: 9, weight: .semibold))
                        Text(day.formatted(.dateTime.day()))
                            .font(.community(.subheadline, weight: isSelected(day) || isToday(day) ? .bold : .semibold))

                        Circle()
                            .fill(dayHasContent(day) ? timeOfDay.commandAccent : .clear)
                            .frame(width: 3, height: 3)
                    }
                    .foregroundStyle(
                        isSelected(day)
                            ? timeOfDay.commandAccent
                            : (isToday(day) ? timeOfDay.commandAccent : timeOfDay.canvasPrimaryText)
                    )
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(isSelected(day) ? timeOfDay.commandAccent : Color.clear)
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(isSelected(day) ? [.isSelected] : [])
            }
        }
        .frame(height: 58)
        .overlay(alignment: .bottom) { Divider() }
        .animation(.easeOut(duration: 0.18), value: selection)
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selection)
        else { return [selection] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private func isToday(_ day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: today)
    }

    private func isSelected(_ day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: selection)
    }

    private func dayHasContent(_ day: Date) -> Bool {
        let weekday = Weekday(calendarWeekday: Calendar.current.component(.weekday, from: day))
        return planner.hasEntries(on: day) || weekday.map { !workouts.workouts(on: $0).isEmpty } == true
    }
}

// MARK: - Up next

private struct HomeUpNextSection: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let date: Date
    let today: Date

    private var isToday: Bool { Calendar.current.isDate(date, inSameDayAs: today) }

    var body: some View {
        Group {
            if let item = items.first {
                NavigationLink {
                    PlannerView(showsBackButton: true)
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(eyebrow(for: item))
                            .font(.community(size: 11, weight: .bold))
                            .tracking(0.45)
                            .foregroundStyle(timeOfDay.commandAccent)

                        HStack(alignment: .center, spacing: 14) {
                            Text(item.title)
                                .font(.community(size: 26, weight: .bold))
                                .tracking(-0.5)
                                .foregroundStyle(timeOfDay.canvasPrimaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(.community(size: 20, weight: .medium))
                                .foregroundStyle(timeOfDay.canvasSecondaryText.opacity(0.7))
                        }
                        .padding(.top, 7)

                        Text(detail(for: item))
                            .font(.community(size: 13, weight: .medium))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                            .padding(.top, 3)

                        Text(scheduleAction)
                            .font(.community(size: 12, weight: .semibold))
                            .foregroundStyle(timeOfDay.commandAccent)
                            .padding(.top, 13)
                    }
                    .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the calendar for the selected day")
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    HomeSectionHeader(
                        title: isToday ? "Up next" : "On \(date.formatted(.dateTime.weekday(.wide)))",
                        action: "Calendar",
                        destination: PlannerView(showsBackButton: true)
                    )

                    HomeEmptyLine(
                        symbol: "calendar",
                        title: isToday ? "Nothing scheduled next" : "Nothing scheduled"
                    )
                        .frame(height: 44)
                }
                .frame(minHeight: 72, alignment: .top)
            }
        }
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(timeOfDay.canvasBorder)
                .frame(height: 1)
        }
    }

    private var items: [PlannerEntry] {
        // Overdue belongs to today only. Reading Thursday and being shown
        // Monday's unfinished tasks says nothing about Thursday.
        let overdue = isToday ? planner.pastDue.filter { !$0.isComplete } : []
        let onDay = planner.entries(on: date).filter { !$0.isComplete || !$0.isCompletable }
        return unique(overdue + onDay).sorted {
            // Priority outranks both of the old keys. Home features one item,
            // so the most important thing must be first.
            if $0.priority.rank != $1.priority.rank {
                return $0.priority.rank < $1.priority.rank
            }
            if isPastDue($0) != isPastDue($1) { return isPastDue($0) }
            return ($0.time ?? "99:99:99") < ($1.time ?? "99:99:99")
        }
    }

    private func unique(_ entries: [PlannerEntry]) -> [PlannerEntry] {
        var seenServerIDs: Set<Int> = []
        var seenLocalIDs: Set<UUID> = []
        return entries.filter { entry in
            if let serverID = entry.serverID { return seenServerIDs.insert(serverID).inserted }
            return seenLocalIDs.insert(entry.id).inserted
        }
    }

    private func isPastDue(_ entry: PlannerEntry) -> Bool {
        planner.pastDue.contains { $0.isSameEntry(as: entry) }
    }

    private func eyebrow(for entry: PlannerEntry) -> String {
        let context: String
        if isPastDue(entry) {
            context = "PAST DUE"
        } else if isToday {
            context = "UP NEXT"
        } else {
            context = date.formatted(.dateTime.weekday(.wide)).uppercased()
        }

        guard let time = entry.displayTime else { return context }
        return "\(context) · \(time)"
    }

    private func detail(for entry: PlannerEntry) -> String {
        let emphasis: String
        if isPastDue(entry) {
            emphasis = "Past due"
        } else if entry.priority == .high {
            emphasis = "High priority"
        } else {
            emphasis = entry.kind.title
        }
        return "\(emphasis) · \(entry.category.title)"
    }

    private var scheduleAction: String {
        if isToday { return "See today's schedule →" }
        let weekday = date.formatted(.dateTime.weekday(.wide))
        return "See \(weekday)'s schedule →"
    }
}

// MARK: - Training

private struct HomeTrainingSection: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let date: Date
    let today: Date

    private var isToday: Bool { Calendar.current.isDate(date, inSameDayAs: today) }

    /// The weekday the plan is keyed by. Workouts repeat weekly, so the plan
    /// for a date is the plan for its weekday.
    private var weekday: Weekday? {
        Weekday(calendarWeekday: Calendar.current.component(.weekday, from: date))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    isToday ? "WORKOUT" : date.formatted(.dateTime.weekday(.wide)).uppercased(),
                    systemImage: workoutSymbol
                )
                .font(.community(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(timeOfDay.commandAccent)

                Spacer()

                NavigationLink {
                    WorkoutsView()
                } label: {
                    Label("Workouts", systemImage: "arrow.up.right")
                        .labelStyle(.titleAndIcon)
                        .font(.community(size: 11, weight: .semibold))
                        .foregroundStyle(timeOfDay.commandAccent)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.community(size: 24, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .lineLimit(2)

                    Text(metadata)
                        .font(.community(size: 13, weight: .medium))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)

                    if let workout, !workout.exercises.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(workout.exercises.prefix(2)) { exercise in
                                HStack(spacing: 8) {
                                    Text(exercise.name)
                                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                                        .lineLimit(1)
                                    Text("\(exercise.sets) sets")
                                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                                }
                                .font(.community(size: 13, weight: .medium))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                NavigationLink {
                    workoutDestination
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: activeSession == nil ? "play.fill" : "arrow.right")
                            .font(.community(size: 20, weight: .bold))
                            .foregroundStyle(timeOfDay.commandAccent)
                            .frame(width: 58, height: 58)
                            .overlay {
                                Circle().strokeBorder(timeOfDay.commandAccent, lineWidth: 2)
                            }

                        Text(activeSession == nil ? (workout == nil ? "Plan" : "Start") : "Continue")
                            .font(.community(size: 13, weight: .bold))
                            .foregroundStyle(timeOfDay.commandAccent)
                    }
                    .frame(width: 76)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actionTitle)
                .accessibilityHint("Opens this workout")
            }

            Rectangle()
                .fill(timeOfDay.canvasBorder)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var workoutDestination: some View {
        if let weekday {
            DayWorkoutView(day: weekday)
        } else {
            WorkoutsView()
        }
    }

    private var workout: Workout? {
        guard let weekday else { return nil }
        return store.workout(on: weekday)
    }

    /// A session is running now, or it is not; it does not belong to a day
    /// being read ahead of time.
    private var activeSession: ActiveWorkoutSession? {
        isToday ? store.activeSession : nil
    }

    private var title: String {
        activeSession?.workoutName
            ?? workout?.name
            ?? (isToday ? "Plan today's workout" : "Nothing planned")
    }

    private var actionTitle: String {
        if activeSession != nil { return "Continue workout" }
        if workout == nil { return "Plan workout" }
        return isToday ? "Start workout" : "Open workout"
    }

    private var metadata: String {
        guard let workout else {
            return isToday ? "No workout is scheduled yet" : "Nothing scheduled for this day"
        }
        if workout.tracksDistance { return workout.type.title }
        let exercises = workout.exercises.count
        return "\(exercises) \(exercises == 1 ? "exercise" : "exercises")  ·  \(workout.totalSets) target sets"
    }

    private var workoutSymbol: String {
        guard let workout else { return "plus" }
        return workout.type.activityIcon.systemName
    }
}

// MARK: - Macros

private struct HomeMacroSection: View {
    @Environment(FoodTrackingStore.self) private var food
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let date: Date
    let today: Date

    private var isToday: Bool { Calendar.current.isDate(date, inSameDayAs: today) }

    var body: some View {
        let total = food.total(on: date)
        let goals = food.goals

        VStack(alignment: .leading, spacing: 7) {
            HomeSectionHeader(
                title: isToday ? "Food today" : "Food on \(date.formatted(.dateTime.weekday(.wide)))",
                action: "Food",
                destination: FoodTrackingView(showsBackButton: true)
            )

            HStack(alignment: .firstTextBaseline) {
                Text("\(total.calories.nutritionText) / \(goals.calories.nutritionText) kcal")
                    .font(.community(.headline, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                Spacer()
                Text("\(remaining(total.calories, goal: goals.calories).nutritionText) left")
                    .font(.community(.caption, weight: .semibold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }

            HomeProgressBar(value: ratio(total.calories, goals.calories), height: 5)

            HStack(spacing: 18) {
                macro("PROTEIN", total.proteinGrams, goals.proteinGrams)
                macro("CARBS", total.carbohydrateGrams, goals.carbohydrateGrams)
                macro("FAT", total.fatGrams, goals.fatGrams)
            }
        }
        .frame(minHeight: 116, alignment: .top)
    }

    private func macro(_ label: String, _ value: Decimal, _ goal: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.community(size: 8, weight: .bold))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            Text("\(value.nutritionText) / \(goal.nutritionText)g")
                .font(.community(.subheadline, weight: .semibold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HomeProgressBar(value: ratio(value, goal), height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ratio(_ value: Decimal, _ goal: Decimal) -> Double {
        guard goal > 0 else { return 0 }
        return min(max(value.nutritionDouble / goal.nutritionDouble, 0), 1)
    }

    private func remaining(_ value: Decimal, goal: Decimal) -> Decimal {
        max(goal - value, 0)
    }
}

private struct HomeProgressBar: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay
    let value: Double
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(timeOfDay.canvasBorder)
                Capsule()
                    .fill(timeOfDay.commandAccent)
                    .frame(width: proxy.size.width * value)
            }
        }
        .frame(height: height)
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

// MARK: - Tasks

private struct HomeRemainingTasksSection: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let date: Date
    let today: Date

    private var isToday: Bool { Calendar.current.isDate(date, inSameDayAs: today) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeSectionHeader(
                title: "Still to do",
                action: tasks.isEmpty ? "Planner" : "\(tasks.count) remaining",
                destination: PlannerView(showsBackButton: true)
            )
            .frame(height: 24)

            if tasks.isEmpty {
                HomeEmptyLine(symbol: "checkmark", title: "Everything is done")
                    .frame(height: 48)
            } else {
                ForEach(tasks.prefix(3)) { task in
                    Button {
                        planner.setComplete(task, true)
                    } label: {
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(timeOfDay.canvasSecondaryText, lineWidth: 1.4)
                                .frame(width: 17, height: 17)

                            Text(task.displayTime ?? "—")
                                .font(.community(.caption, weight: .semibold))
                                .foregroundStyle(timeOfDay.canvasSecondaryText)
                                .frame(width: 40, alignment: .leading)

                            // The same glyph Up Next uses, for the same reason:
                            // this list reorders for priority, and a row that
                            // jumped the queue should say why it did.
                            if task.priority.badge != nil {
                                Image(systemName: "exclamationmark")
                                    .font(.community(size: 9, weight: .black))
                                    .foregroundStyle(task.priority.tint)
                            }

                            Text(task.title)
                                .font(.community(.subheadline, weight: .semibold))
                                .foregroundStyle(timeOfDay.canvasPrimaryText)
                                .lineLimit(1)

                            Spacer(minLength: 6)

                            if isPastDue(task) {
                                Text("PAST DUE")
                                    .font(.community(size: 8, weight: .bold))
                                    .tracking(0.5)
                                    .foregroundStyle(timeOfDay.commandAccent)
                            } else if let badge = task.priority.badge {
                                Text(badge)
                                    .font(.community(size: 8, weight: .bold))
                                    .tracking(0.5)
                                    .foregroundStyle(task.priority.tint)
                            }
                        }
                        .frame(height: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if task.id != tasks.prefix(3).last?.id {
                        Rectangle()
                            .fill(timeOfDay.canvasBorder)
                            .frame(height: 1)
                    }
                }
            }
        }
        .frame(minHeight: 102, alignment: .top)
    }

    private var tasks: [PlannerEntry] {
        // As in Up Next: what is overdue is overdue as of today, and has
        // nothing to say about a day being read ahead.
        let overdue = isToday
            ? planner.pastDue.filter { $0.isCompletable && !$0.isComplete }
            : []
        let onDay = planner.entries(on: date).filter { $0.isCompletable && !$0.isComplete }
        var seenServerIDs: Set<Int> = []
        var seenLocalIDs: Set<UUID> = []
        let merged = (overdue + onDay).filter { entry in
            if let serverID = entry.serverID { return seenServerIDs.insert(serverID).inserted }
            return seenLocalIDs.insert(entry.id).inserted
        }
        // High first; everything else keeps the order it was merged in, which
        // already reads right — overdue ahead of the day, then the order the
        // server sent. Sorted through the index because Swift's sort is not
        // stable, so equal ranks would otherwise shuffle between reads.
        return merged.enumerated()
            .sorted {
                ($0.element.priority.rank, $0.offset)
                    < ($1.element.priority.rank, $1.offset)
            }
            .map(\.element)
    }

    private func isPastDue(_ task: PlannerEntry) -> Bool {
        planner.pastDue.contains { $0.isSameEntry(as: task) }
    }
}

// MARK: - Shared home pieces

private struct HomeSectionHeader<Destination: View>: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let title: String
    let action: String
    let destination: Destination

    var body: some View {
        HStack {
            Text(title)
                .font(.community(size: 16, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)

            Spacer()

            NavigationLink {
                destination
            } label: {
                HStack(spacing: 4) {
                    Text(action)
                    Image(systemName: "arrow.up.right")
                }
                .font(.community(size: 11, weight: .semibold))
                .foregroundStyle(timeOfDay.commandAccent)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 24)
    }
}

private struct HomeEmptyLine: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.community(.caption, weight: .semibold))
                .foregroundStyle(timeOfDay.commandAccent)
            Text(title)
                .font(.community(.subheadline))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            Spacer()
        }
    }
}

private struct HomePersistenceError: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let message: String
    /// Nil where the store has no retry to offer, in which case the line says
    /// what went wrong and does not pretend there is a button that fixes it.
    var retry: (() -> Void)?

    init(message: String, retry: (() -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(timeOfDay.commandAccent)
            VStack(alignment: .leading, spacing: 7) {
                Text(message).font(.community(.footnote))
                if let retry {
                    Button("Retry", action: retry)
                        .font(.community(.footnote, weight: .semibold))
                }
            }
            Spacer()
        }
        .foregroundStyle(timeOfDay.canvasPrimaryText)
        .padding(.vertical, 8)
    }
}

private struct HomeLoadingOverlay: View {
    let timeOfDay: HomeTimeOfDay

    var body: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            ProgressView("Loading workouts…")
                .padding(18)
                .foregroundStyle(timeOfDay.primaryText)
                .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private extension HomeTimeOfDay {
    /// The approved command-center orange remains stable across appearances.
    var commandAccent: Color { RepbasePalette.caramel }
}

#Preview {
    NavigationStack { ContentView() }
        .environment(WorkoutStore.preview)
        .environment(PlannerStore.preview)
        .environment(FoodTrackingStore.preview)
        .environment(ActivityStore())
        .environment(SocialProfileStore.preview)
        .environment(AuthenticationStore(configuration: .current))
}
