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

            // The navigation stack and the bottom bar belong to
            // `RepbaseRootView`, so the bar stays put wherever this page
            // navigates to rather than existing only here.
            Group {
                ScrollView {
                    VStack(spacing: 0) {
                        HomeHeader(date: context.date)

                        HomeCategorySection(
                            number: "01",
                            eyebrow: "ORGANIZE",
                            title: "Calendar",
                            detail: "Give workouts a time and manage the rest of your day.",
                            symbol: "calendar",
                            destination: PlannerView()
                        ) {
                            VStack(spacing: 14) {
                                HomeCalendarCard()
                                TodaysTasksList()
                            }
                        }
                        .padding(.top, 28)

                        HomeCategorySection(
                            number: "02",
                            eyebrow: "TRAIN",
                            title: "Workout",
                            detail: "Plan the week, build sessions, and start training.",
                            symbol: "dumbbell.fill",
                            destination: WorkoutsView()
                        ) {
                            HStack(alignment: .top, spacing: 16) {
                                WeeklyPlanCard()
                                TodayWorkoutCard()
                            }
                        }
                        .padding(.top, 28)

                        HomeCategorySection(
                            number: "03",
                            eyebrow: "NOURISH",
                            title: "Food",
                            detail: "Log meals and keep daily nutrition in view.",
                            symbol: "fork.knife",
                            destination: FoodTrackingView()
                        ) {
                            FoodSummaryWidget()
                        }
                        .padding(.top, 28)

                        if let error = workoutStore.persistenceError {
                            persistenceErrorCard(error)
                                .padding(.top, 18)
                        }
                    }
                    .padding(.horizontal, RepbaseDesign.pageInset)
                    .padding(.top, 18)
                    // The custom navigation bar is inset outside this tab's
                    // navigation stack, so its height is not included in the
                    // ScrollView's natural content boundary. Keep enough real
                    // scrollable space for the final section to move fully
                    // above both the bar and the home indicator.
                    .padding(.bottom, 118)
                }
                .scrollIndicators(.hidden)
                .toolbar(.hidden, for: .navigationBar)
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
        .background(HomeTimeOfDay.day.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius))
    }

    private func loadingOverlay(timeOfDay: HomeTimeOfDay) -> some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            ProgressView("Loading workouts…")
                .padding(18)
                .foregroundStyle(timeOfDay.primaryText)
                .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius))
        }
    }
}

/// A clearly labelled doorway into one of the app's three jobs. The preview
/// below the rule keeps Home useful, while the heading makes it immediately
/// obvious where the full workflow lives.
private struct HomeCategorySection<Destination: View, Content: View>: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let number: String
    let eyebrow: String
    let title: String
    let detail: String
    let symbol: String
    let destination: Destination
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                destination
            } label: {
                VStack(spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(eyebrow)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.35)
                            .foregroundStyle(timeOfDay.accent)

                        Spacer()

                        Label("View", systemImage: "arrow.right")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(timeOfDay.secondaryText)
                    }

                    Rectangle()
                        .fill(timeOfDay.canvasBorder)
                        .frame(height: 1)

                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(timeOfDay.accent)
                            .frame(width: 38, height: 38)
                            .background(timeOfDay.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(title)
                                .font(.system(size: 22, weight: .bold))
                                .tracking(-0.35)
                                .foregroundStyle(timeOfDay.primaryText)
                            Text(detail)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(timeOfDay.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the full \(title.lowercased()) section")

            content
        }
    }
}

private struct HomeHeader: View {
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let date: Date

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("REPBASE  /  \(date.formatted(.dateTime.weekday(.wide)).uppercased())")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.35)
                    .foregroundStyle(timeOfDay.accent)
                Text(headline)
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.65)
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
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
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(timeOfDay.accent)
                .frame(width: 44, height: 44)
                .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(timeOfDay.border, lineWidth: 1)
                }
        }
        .disabled(authentication.isWorking)
        .accessibilityLabel("Account")
    }

    private var accountInitial: String {
        guard case .signedIn(let user) = authentication.phase else { return "R" }
        return String(user.displayName.prefix(1)).uppercased()
    }

    private var headline: String {
        guard case .signedIn(let user) = authentication.phase else { return "Hello" }
        let firstName = user.displayName.split(separator: " ").first.map(String.init) ?? user.displayName
        return "Hello \(firstName)"
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
    @State private var scrollOffset: CGFloat = 0

    private let listHeight: CGFloat = 103
    private let scrollTrackHeight: CGFloat = 95

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                WorkoutsView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center) {
                        Text("PLAN WORKOUTS")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.7)
                        Spacer(minLength: 4)
                        Text("\(items.count)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                    Text("Workouts")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the weekly workout plan")

            Spacer(minLength: 12)

            ScrollView(.vertical) {
                LazyVStack(spacing: 7) {
                    ForEach(items) { item in
                        planRow(item)
                    }
                    if items.isEmpty {
                        emptyPlanRow
                    }
                }
                .padding(.trailing, showsScrollBar ? 8 : 0)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newOffset in
                scrollOffset = newOffset
            }
            .frame(height: listHeight)
            .overlay(alignment: .trailing) {
                if showsScrollBar {
                    ZStack(alignment: .top) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                        Capsule()
                            .fill(Color.white.opacity(0.72))
                            .frame(height: scrollThumbHeight)
                            .offset(y: scrollThumbOffset)
                    }
                    .frame(width: 3, height: scrollTrackHeight)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 214, maxHeight: 214, alignment: .topLeading)
        .foregroundStyle(Color.white)
        .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: timeOfDay.shadow, radius: 8, x: 0, y: 3)
    }

    private var items: [PlannedWorkoutItem] {
        Weekday.allCases.flatMap { day in
            store.workouts(on: day).map { PlannedWorkoutItem(day: day, workout: $0) }
        }
    }

    private var listContentHeight: CGFloat {
        let rowCount = max(items.count, 1)
        return CGFloat(rowCount * 48 + max(rowCount - 1, 0) * 7)
    }

    private var showsScrollBar: Bool {
        listContentHeight > listHeight
    }

    private var scrollThumbHeight: CGFloat {
        max(26, scrollTrackHeight * listHeight / listContentHeight)
    }

    private var scrollThumbOffset: CGFloat {
        let contentTravel = max(listContentHeight - listHeight, 1)
        let progress = min(max(scrollOffset / contentTravel, 0), 1)
        return (scrollTrackHeight - scrollThumbHeight) * progress
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
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: RepbaseDesign.controlRadius))
    }

    private var emptyPlanRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.caption.weight(.bold))
            Text("Build your week").font(.system(size: 11, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: RepbaseDesign.controlRadius))
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
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                }
                .foregroundStyle(Color.white)
                .padding(.leading, 18)
                .padding(.trailing, 5)
                .frame(height: 48)
                .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: RepbaseDesign.controlRadius))
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
                .clipShape(RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius))
            }
            .overlay {
                RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
            }
            .shadow(color: timeOfDay.shadow, radius: 8, x: 0, y: 3)
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

#Preview {
    ContentView()
        .environment(WorkoutStore.preview)
        .environment(PlannerStore())
        .environment(FoodTrackingStore.preview)
        .environment(SocialProfileStore.preview)
        .environment(
            AuthenticationStore(configuration: .current)
        )
}
