//
//  ContentView.swift
//  IOS Frontend
//
//  Home is a command center, not a stack of dashboard widgets. Every section
//  below reads from an existing store and routes into an existing feature.
//

import SwiftUI

struct ContentView: View {
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(PlannerStore.self) private var plannerStore
    @Environment(FoodTrackingStore.self) private var foodStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    HomeCommandHeader(date: context.date)
                    HomeWeekStrip(date: context.date)
                    HomeUpNextSection(date: context.date)
                    HomeTrainingSection(date: context.date)
                    HomeMacroSection(date: context.date)
                    HomeRemainingTasksSection(date: context.date)

                    // Every store that Home reads from, not just workouts.
                    // A task that failed to tick rolled back in silence, and a
                    // food read that failed left the macros reading zero with
                    // nothing to say why.
                    if let error = workoutStore.persistenceError {
                        HomePersistenceError(message: error) {
                            workoutStore.retryPersistence()
                        }
                    }
                    if let error = plannerStore.persistenceError {
                        HomePersistenceError(message: error) {
                            plannerStore.retry()
                        }
                    }
                    if let error = foodStore.errorMessage {
                        HomePersistenceError(message: error, retry: nil)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, RepbaseDesign.bottomBarClearance)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if workoutStore.isLoading {
                    HomeLoadingOverlay(timeOfDay: timeOfDay)
                }
            }
            .homeTimeScreen(timeOfDay)
        }
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
            VStack(alignment: .leading, spacing: 3) {
                Text("\(greeting.uppercased()), \(firstName.uppercased())")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(timeOfDay.commandAccent)

                Text("Your day.")
                    .font(.largeTitle.weight(.bold))
                    .tracking(-0.6)
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
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
                .font(.subheadline.weight(.bold))
                .foregroundStyle(timeOfDay.commandAccent)
                .frame(width: 44, height: 44)
                .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(timeOfDay.commandAccent, lineWidth: 1)
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
        switch timeOfDay {
        case .dawn: "Good morning"
        case .day: "Good afternoon"
        case .dusk, .night: "Good evening"
        }
    }
}

// MARK: - Week

private struct HomeWeekStrip: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(WorkoutStore.self) private var workouts
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let date: Date

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekDates, id: \.self) { day in
                NavigationLink {
                    PlannerView()
                        // The planner reads its day from the store, so the tap
                        // sets it before the push. Without this every date in
                        // the strip opened on whatever was last selected.
                        .onAppear { planner.select(day) }
                } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.system(size: 9, weight: .semibold))
                        Text(day.formatted(.dateTime.day()))
                            .font(.subheadline.weight(isToday(day) ? .bold : .semibold))

                        Circle()
                            .fill(dayHasContent(day) ? (isToday(day) ? Color.white : timeOfDay.commandAccent) : .clear)
                            .frame(width: 3, height: 3)
                    }
                    .foregroundStyle(isToday(day) ? Color.white : timeOfDay.canvasPrimaryText)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background {
                        if isToday(day) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(timeOfDay.commandAccent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            }
        }
        .frame(height: 64)
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [date] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private func isToday(_ day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: date)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HomeSectionHeader(title: "UP NEXT", action: "OPEN CALENDAR", destination: PlannerView())

            if items.isEmpty {
                HomeEmptyLine(symbol: "calendar", title: "Nothing scheduled next")
                    .frame(height: 44)
            } else {
                ForEach(items.prefix(2)) { item in
                    HStack(spacing: 8) {
                        Text(item.displayTime ?? "—")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                            .frame(width: 40, alignment: .leading)

                        Circle()
                            .fill(item.category.tint)
                            .frame(width: 6, height: 6)

                        Text(item.title)
                            .font(.subheadline.weight(item.isCompletable ? .semibold : .regular))
                            .foregroundStyle(timeOfDay.canvasPrimaryText)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        Text(status(for: item))
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(isPastDue(item) ? timeOfDay.commandAccent : timeOfDay.canvasSecondaryText)
                    }
                    .frame(height: 22)
                }
            }

            Rectangle()
                .fill(timeOfDay.canvasBorder)
                .frame(height: 1)
                .padding(.top, 3)
        }
        .frame(minHeight: 72, alignment: .top)
    }

    private var items: [PlannerEntry] {
        let overdue = planner.pastDue.filter { !$0.isComplete }
        let today = planner.entries(on: date).filter { !$0.isComplete || !$0.isCompletable }
        return unique(overdue + today).sorted {
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

    private func status(for entry: PlannerEntry) -> String {
        if isPastDue(entry) { return "PAST DUE" }
        return entry.kind == .event ? "EVENT" : entry.category.title.uppercased()
    }
}

// MARK: - Training

private struct HomeTrainingSection: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HomeSectionHeader(title: "TRAINING  /  TODAY", action: "OPEN WORKOUTS", destination: WorkoutsView())

            NavigationLink {
                workoutDestination
            } label: {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.title.weight(.bold))
                            .tracking(-0.35)
                            .foregroundStyle(timeOfDay.canvasPrimaryText)
                            .lineLimit(1)
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: workoutSymbol)
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(timeOfDay.commandAccent)
                        .frame(width: 54, height: 54)
                }
                .frame(minHeight: 66)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NavigationLink {
                workoutDestination
            } label: {
                HStack {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: store.activeSession == nil ? "play.fill" : "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(timeOfDay.commandAccent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .foregroundStyle(RepbasePalette.cream)
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .frame(height: 44)
                .background(timeOfDay.ink, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens today's workout")

            Rectangle()
                .fill(timeOfDay.canvasBorder)
                .frame(height: 1)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var workoutDestination: some View {
        if let day = store.today {
            DayWorkoutView(day: day)
        } else {
            WorkoutsView()
        }
    }

    private var workout: Workout? {
        guard let today = store.today else { return nil }
        return store.workout(on: today)
    }

    private var title: String {
        store.activeSession?.workoutName ?? workout?.name ?? "Plan today's workout"
    }

    private var actionTitle: String {
        if store.activeSession != nil { return "Continue workout" }
        return workout == nil ? "Plan workout" : "Start workout"
    }

    private var metadata: String {
        guard let workout else { return "No workout is scheduled yet" }
        if workout.tracksDistance { return workout.type.title }
        let exercises = workout.exercises.count
        return "\(exercises) \(exercises == 1 ? "exercise" : "exercises")  ·  \(workout.totalSets) target sets"
    }

    private var workoutSymbol: String {
        guard let workout else { return "plus" }
        // `return` is required: a switch is only an expression when it is the
        // whole body, and the guard above makes this a statement.
        return switch workout.type {
        case .lifting: "dumbbell.fill"
        case .running: "figure.run"
        case .biking: "bicycle"
        case .swimming: "figure.pool.swim"
        }
    }
}

// MARK: - Macros

private struct HomeMacroSection: View {
    @Environment(FoodTrackingStore.self) private var food
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let date: Date

    var body: some View {
        let total = food.total(on: date)
        let goals = food.goals

        VStack(alignment: .leading, spacing: 7) {
            HomeSectionHeader(title: "MACROS TODAY", action: "OPEN FOOD", destination: FoodTrackingView())

            HStack(alignment: .firstTextBaseline) {
                Text("\(total.calories.nutritionText) / \(goals.calories.nutritionText) kcal")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                Spacer()
                Text("\(remaining(total.calories, goal: goals.calories).nutritionText) left")
                    .font(.caption.weight(.semibold))
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
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            Text("\(value.nutritionText) / \(goal.nutritionText)g")
                .font(.subheadline.weight(.semibold))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeSectionHeader(
                title: "STILL TO DO",
                action: "\(tasks.count) REMAINING  ·  OPEN",
                destination: PlannerView()
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
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(timeOfDay.canvasSecondaryText)
                                .frame(width: 40, alignment: .leading)

                            Text(task.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(timeOfDay.canvasPrimaryText)
                                .lineLimit(1)

                            Spacer(minLength: 6)

                            if isPastDue(task) {
                                Text("PAST DUE")
                                    .font(.system(size: 8, weight: .bold))
                                    .tracking(0.5)
                                    .foregroundStyle(timeOfDay.commandAccent)
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
        let overdue = planner.pastDue.filter { $0.isCompletable && !$0.isComplete }
        let today = planner.entries(on: date).filter { $0.isCompletable && !$0.isComplete }
        var seenServerIDs: Set<Int> = []
        var seenLocalIDs: Set<UUID> = []
        return (overdue + today).filter { entry in
            if let serverID = entry.serverID { return seenServerIDs.insert(serverID).inserted }
            return seenLocalIDs.insert(entry.id).inserted
        }
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
                .font(.system(size: 9, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(timeOfDay.commandAccent)

            Spacer()

            NavigationLink {
                destination
            } label: {
                HStack(spacing: 4) {
                    Text(action)
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 18)
    }
}

private struct HomeEmptyLine: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(timeOfDay.commandAccent)
            Text(title)
                .font(.subheadline)
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
                Text(message).font(.footnote)
                if let retry {
                    Button("Retry", action: retry)
                        .font(.footnote.weight(.semibold))
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
    /// The approved command-center orange, softened after sunset so the
    /// hierarchy stays legible without turning the night screen neon.
    var commandAccent: Color {
        switch self {
        case .dawn, .day: Color(hex: 0xF86722)
        case .dusk: Color(hex: 0xFF7540)
        case .night: Color(hex: 0xFF966D)
        }
    }
}

#Preview {
    NavigationStack { ContentView() }
        .environment(WorkoutStore.preview)
        .environment(PlannerStore.preview)
        .environment(FoodTrackingStore.preview)
        .environment(SocialProfileStore.preview)
        .environment(AuthenticationStore(configuration: .current))
}
