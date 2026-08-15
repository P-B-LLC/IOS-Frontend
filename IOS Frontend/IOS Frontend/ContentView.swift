//
//  ContentView.swift
//  IOS Frontend
//
//  Created by user299988 on 8/9/26.
//

import SwiftUI

/// The app's time-aware dashboard. Every value and destination is backed by an
/// existing workout, food, or account feature; the presentation changes with
/// the local time without changing the underlying behavior.
struct ContentView: View {
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(WorkoutStore.self) private var workoutStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            NavigationStack {
                ScrollView {
                    VStack(spacing: 14) {
                        HomeHeader(date: context.date)
                        HomeWeekdaySelector(date: context.date)

                        HStack(alignment: .top, spacing: 16) {
                            WeeklyPlanCard()
                            TodayWorkoutCard()
                        }

                        HomeCalendarRow()

                        FoodSummaryWidget()

                        TodaysActivityCard()

                        if let error = workoutStore.persistenceError {
                            persistenceErrorCard(error)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom, spacing: 8) {
                    HomeBottomNavigation()
                        .padding(.horizontal, 24)
                }
                .overlay {
                    if workoutStore.isLoading {
                        loadingOverlay(timeOfDay: timeOfDay)
                    }
                }
                .homeTimeScreen(timeOfDay)
            }
        }
    }

    private func persistenceErrorCard(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(HomeTimeOfDay.day.accent)
            VStack(alignment: .leading, spacing: 7) {
                Text(error)
                    .font(.footnote)
                Button("Retry") { workoutStore.retryPersistence() }
                    .font(.footnote.weight(.semibold))
            }
            Spacer()
        }
        .padding(14)
        .background(HomeTimeOfDay.day.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private func loadingOverlay(timeOfDay: HomeTimeOfDay) -> some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            ProgressView("Loading workouts…")
                .padding(18)
                .foregroundStyle(timeOfDay.primaryText)
                .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct HomeHeader: View {
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let date: Date

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(timeOfDay.label) · \(date.formatted(.dateTime.weekday(.wide)).uppercased())")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(timeOfDay.secondaryText)
                Text("Ready to train?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Your plan and nutrition, in one place.")
                    .font(.system(size: 13))
                    .foregroundStyle(timeOfDay.secondaryText)
            }

            Spacer(minLength: 12)
            accountMenu
        }
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
            Button(
                "Sign Out",
                systemImage: "rectangle.portrait.and.arrow.right",
                role: .destructive
            ) {
                Task { await authentication.signOut() }
            }
        } label: {
            Text(accountInitial)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(timeOfDay.primaryText)
                .frame(width: 44, height: 44)
                .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 15))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(timeOfDay.border, lineWidth: 1)
                }
                .shadow(color: timeOfDay.shadow.opacity(0.7), radius: 7, x: 3, y: 5)
        }
        .disabled(authentication.isWorking)
        .accessibilityLabel("Account")
    }

    private var accountInitial: String {
        guard case .signedIn(let user) = authentication.phase else { return "R" }
        return String(user.displayName.prefix(1)).uppercased()
    }
}

private struct HomeWeekdaySelector: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let date: Date

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Weekday.allCases.indices, id: \.self) { index in
                let day = Weekday.allCases[index]
                NavigationLink {
                    DayWorkoutView(day: day)
                } label: {
                    VStack(spacing: 0) {
                        Text(day.shortName.uppercased())
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(0.4)
                        Text(dayDate(at: index).formatted(.dateTime.day()))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(foreground(for: day))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(fill(for: day), in: RoundedRectangle(cornerRadius: isToday(day) ? 16 : 14))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the \(day.fullName) workout")
            }
        }
        .padding(6)
        .background(timeOfDay.selectorSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(timeOfDay.border, lineWidth: 1)
        }
        .shadow(color: timeOfDay.shadow, radius: 8, x: 5, y: 8)
    }

    private func isToday(_ day: Weekday) -> Bool { store.today == day }

    private func isCompleted(_ day: Weekday) -> Bool {
        store.completedSessions.contains { completion in
            completion.session.day == day && Calendar.current.isDate(
                completion.endedAt,
                equalTo: date,
                toGranularity: .weekOfYear
            )
        }
    }

    private func fill(for day: Weekday) -> Color {
        if isToday(day) { return timeOfDay.accent }
        if isCompleted(day) { return timeOfDay.completedDaySurface }
        if store.workoutCount(on: day) > 0 { return timeOfDay.plannedDaySurface }
        return timeOfDay.emptyDaySurface
    }

    private func foreground(for day: Weekday) -> Color {
        if isToday(day) || isCompleted(day) { return Color(hex: 0x080607) }
        if store.workoutCount(on: day) > 0 || timeOfDay.usesDarkAppearance { return Color(hex: 0xF7F7F8) }
        return timeOfDay.primaryText
    }

    private func dayDate(at index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index, to: mondayOfCurrentWeek) ?? date
    }

    private var mondayOfCurrentWeek: Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: start) ?? start
    }
}

private struct PlannedWorkoutItem: Identifiable {
    let day: Weekday
    let workout: Workout
    var id: Workout.ID { workout.id }
}

private struct WeeklyPlanCard: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    var body: some View {
        NavigationLink {
            WorkoutsView()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("THIS WEEK")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.7)
                        Text("Weekly\nPlan")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .lineSpacing(-2)
                    }
                    Spacer(minLength: 4)
                    Text("\(items.count)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.18), in: Circle())
                }

                Spacer(minLength: 12)

                VStack(spacing: 7) {
                    ForEach(Array(items.prefix(2))) { item in
                        planRow(item)
                    }
                    if items.isEmpty {
                        emptyPlanRow
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 214, alignment: .topLeading)
            .foregroundStyle(Color(hex: 0x1B1415))
            .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 24))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: timeOfDay.shadow, radius: 12, x: 5, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the weekly workout plan")
    }

    private var items: [PlannedWorkoutItem] {
        Weekday.allCases.flatMap { day in
            store.workouts(on: day).map { PlannedWorkoutItem(day: day, workout: $0) }
        }
    }

    private func planRow(_ item: PlannedWorkoutItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: completed(item.day) ? "checkmark" : item.workout.type.symbolName)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.32), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(item.workout.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(item.day.shortName.uppercased())
                    .font(.system(size: 8, weight: .medium))
                    .opacity(0.68)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 15))
    }

    private var emptyPlanRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.caption.weight(.bold))
            Text("Build your week").font(.system(size: 11, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 15))
    }

    private func completed(_ day: Weekday) -> Bool {
        store.completedSessions.contains { $0.session.day == day }
    }
}

private struct TodayWorkoutCard: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    var body: some View {
        NavigationLink {
            if let today = store.today {
                DayWorkoutView(day: today)
            } else {
                WorkoutsView()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(Date().formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color(hex: 0xACA6A5))
                Text(prompt)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xF7F7F8).opacity(0.72))
                    .padding(.top, 9)
                Text(title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 2)

                Spacer(minLength: 12)

                Text(meta)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(hex: 0xACA6A5))
                    .lineLimit(2)

                HStack {
                    Text(buttonTitle)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: store.activeSession == nil ? "arrow.right" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0xF7F7F8))
                        .frame(width: 38, height: 38)
                        .background(timeOfDay.ink, in: Circle())
                }
                .foregroundStyle(Color(hex: 0x1B1415))
                .padding(.leading, 18)
                .padding(.trailing, 5)
                .frame(height: 48)
                .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 16))
                .padding(.top, 10)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 214, alignment: .topLeading)
            .foregroundStyle(Color(hex: 0xF7F7F8))
            .background {
                LinearGradient(
                    colors: [timeOfDay.ink, timeOfDay.heroEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
            }
            .shadow(color: timeOfDay.shadow, radius: 12, x: 5, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens today's workout")
    }

    private var workout: Workout? {
        guard let today = store.today else { return nil }
        return store.workout(on: today)
    }

    private var title: String { store.activeSession?.workoutName ?? workout?.name ?? "Plan Today" }
    private var prompt: String { store.activeSession == nil ? "Ready to train?" : "Workout in progress" }
    private var buttonTitle: String { store.activeSession == nil ? (workout == nil ? "Plan" : "Start") : "Continue" }

    private var meta: String {
        guard let workout else { return "No workout is scheduled yet" }
        if workout.tracksDistance { return workout.type.title }
        let exerciseCount = workout.exercises.count
        let exercises = exerciseCount == 1 ? "exercise" : "exercises"
        let sets = workout.totalSets == 1 ? "set" : "sets"
        return "\(exerciseCount) \(exercises) · \(workout.totalSets) \(sets)"
    }
}

private struct HomeBottomNavigation: View {
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(\.homeTimeOfDay) private var timeOfDay

    var body: some View {
        HStack(spacing: 3) {
            Label("Home", systemImage: "house.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1B1415))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 16))

            navLink("Workouts", systemImage: "dumbbell.fill") { WorkoutsView() }
            navLink("Planner", systemImage: "checklist") { PlannerView() }
            navLink("Food", systemImage: "fork.knife") { FoodTrackingView() }

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
                compactItem("Account", systemImage: "person")
            }
            .disabled(authentication.isWorking)
        }
        .padding(6)
        .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(timeOfDay.border, lineWidth: 1) }
        .shadow(color: timeOfDay.shadow, radius: 10, x: 5, y: 7)
    }

    private func navLink<Destination: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            compactItem(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func compactItem(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 14, weight: .semibold))
            Text(title).font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(timeOfDay.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }
}

#Preview {
    ContentView()
        .environment(WorkoutStore.preview)
        .environment(PlannerStore())
        .environment(FoodTrackingStore.preview)
        .environment(
            AuthenticationStore(configuration: .current)
        )
}
