//
//  TrainingTabView.swift
//  IOS Frontend
//
//  Workouts and food on one tab: what you did, and what you ate.
//

import SwiftUI

/// The two halves of a training day, behind one switch.
///
/// They were a tab each, which spent two of five slots on things a person
/// moves between constantly anyway — and left no room for the feed. The switch
/// sits at the top of this tab rather than being a second bar at the bottom, so
/// there is still only one control in the app that changes area.
struct TrainingTabView: View {
    nonisolated enum Half: String, CaseIterable, Identifiable {
        case workouts
        case food

        var id: String { rawValue }

        var title: String {
            switch self {
            case .workouts: "Workouts"
            case .food: "Food"
            }
        }

        var symbol: String {
            switch self {
            case .workouts: ActivityIconKind.lifting.systemName
            case .food: "fork.knife"
            }
        }
    }

    /// Which half is showing.
    ///
    /// Held by the root rather than here, so Home can open this tab straight
    /// onto Food. Logging food from Home used to push the food page onto
    /// Home's own stack, which left the bottom bar lit on Home while you
    /// read it.
    @Binding var half: Half

    @State private var quickAction: TrainingQuickAction?
    @State private var isShowingQuickActions = false

    init(half: Binding<Half>) {
        _half = half
#if DEBUG
        // Opens the row on launch. The tiles are two taps in, and the
        // simulator cannot be tapped from a command line.
        if ProcessInfo.processInfo.environment["REPBASE_QUICK_ACTIONS"] != nil {
            _isShowingQuickActions = State(initialValue: true)
        }
#endif
    }

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        VStack(spacing: 0) {
            HStack {
                RytivoBrandLockup(size: 24)
                Spacer()
                Text(half.title)
                    .font(.community(.title3, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 8)

            switcher(timeOfDay: timeOfDay)

            if isShowingQuickActions {
                quickActionTiles(timeOfDay: timeOfDay)
            }

            switch half {
            case .workouts: WorkoutsView()
            case .food: FoodTrackingView()
            }
        }
        .homeTimeScreen(timeOfDay)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isShowingQuickActions)
        // The two halves offer different actions, so an open row would be
        // showing the wrong ones the moment the switch moves.
        .onChange(of: half) { isShowingQuickActions = false }
#if DEBUG
        // `half` belongs to the root now, so the launch flag sets it here
        // rather than in init.
        .task {
            let flag = ProcessInfo.processInfo.environment["REPBASE_QUICK_ACTIONS"]
            if flag == "food" {
                half = .food
            }
            // Straight into one of the sheets the row raises, which is a tap
            // past a tap.
            if let named = flag, let action = TrainingQuickAction(rawValue: named) {
                quickAction = action
                isShowingQuickActions = false
            }
        }
#endif
        .fullScreenCover(item: $quickAction) { action in
            quickActionDestination(action)
        }
    }

    private func switcher(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 8) {
            halfPicker(timeOfDay: timeOfDay)
            quickActionButton(timeOfDay: timeOfDay)
        }
        .padding(.horizontal, RepbaseDesign.pageInset)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.18), value: half)
    }

    private func halfPicker(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 3) {
            ForEach(Half.allCases) { item in
                Button {
                    half = item
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.community(size: 13, weight: .semibold))
                        .foregroundStyle(item == half ? timeOfDay.onPrimaryAction : timeOfDay.canvasSecondaryText)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if item == half {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(timeOfDay.primaryActionSurface)
                                    .shadow(color: Color.black.opacity(0.16), radius: 6, x: 0, y: 3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == half ? [.isSelected] : [])
            }
        }
        .padding(4)
        .repbaseInsetSurface(cornerRadius: 13)
    }

    /// Opens the actions, beside the switcher.
    ///
    /// It used to be a button floating over the page, which meant it sat on
    /// top of whatever happened to scroll under it -- the weekly-goal row, on
    /// a phone -- and it was already as low as it could go, ten points above
    /// the bottom bar. Up here it covers nothing and is always in one place.
    private func quickActionButton(timeOfDay: HomeTimeOfDay) -> some View {
        Button {
            isShowingQuickActions.toggle()
        } label: {
            Image(systemName: isShowingQuickActions ? "xmark" : "plus")
                .font(.community(size: 16, weight: .bold))
                .foregroundStyle(timeOfDay.onPrimaryAction)
                // 48 square, comfortably over the 44pt minimum.
                .frame(width: 48, height: 48)
                .background(
                    timeOfDay.primaryActionSurface,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isShowingQuickActions
                ? "Close quick actions"
                : (half == .food ? "Food actions" : "Workout actions")
        )
    }

    /// A tile per action rather than a menu.
    ///
    /// A system menu is the right control for a list of commands with names,
    /// and these are two or three things with icons -- the menu spent a
    /// full-width popover, a dimmed backdrop and an animation on saying what
    /// three tiles say in place. The row is right-aligned so it opens
    /// underneath the button that summoned it.
    private func quickActionTiles(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            ForEach(actions) { action in
                Button {
                    quickAction = action
                    isShowingQuickActions = false
                } label: {
                    Image(systemName: action.symbol)
                        .font(.community(size: 17, weight: .semibold))
                        .foregroundStyle(timeOfDay.accent)
                        .frame(width: 48, height: 48)
                        .repbaseDepthSurface(cornerRadius: 15)
                        // The tile is the whole target; without this only the
                        // glyph itself answers a tap.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
                .accessibilityHint(action.detail)
            }
        }
        .padding(.horizontal, RepbaseDesign.pageInset)
        .padding(.bottom, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var actions: [TrainingQuickAction] {
        switch half {
        case .food: [.postFood, .planMeals, .savedMeals]
        case .workouts: [.postWorkout, .savedWorkouts]
        }
    }

    @ViewBuilder
    private func quickActionDestination(_ action: TrainingQuickAction) -> some View {
        switch action {
        case .postFood:
            PostComposerView(source: .meal)
        case .postWorkout:
            PostComposerView(source: .workout)
        case .savedMeals:
            NavigationStack { SavedMealsView(referenceDate: Date()) }
        case .planMeals:
            NavigationStack { MealPlanView(initialDate: Date()) }
        case .savedWorkouts:
            NavigationStack { SavedWorkoutsView() }
        }
    }

}

private enum TrainingQuickAction: String, Identifiable {
    case postFood, planMeals, savedMeals, postWorkout, savedWorkouts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .postFood: "Post food"
        case .planMeals: "Plan meals"
        case .savedMeals: "Saved meals"
        case .postWorkout: "Post workout"
        case .savedWorkouts: "Saved workouts"
        }
    }

    var detail: String {
        switch self {
        case .postFood: "Share today’s nutrition"
        case .planMeals: "Build and preview a day"
        case .savedMeals: "Reuse meals you love"
        case .postWorkout: "Share a completed session"
        case .savedWorkouts: "Reuse a workout plan"
        }
    }

    var symbol: String {
        switch self {
        case .postFood, .postWorkout: "square.and.arrow.up"
        case .planMeals: "calendar.badge.plus"
        case .savedMeals, .savedWorkouts: "bookmark.fill"
        }
    }

}
