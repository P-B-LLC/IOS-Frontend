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
            case .workouts: "dumbbell.fill"
            case .food: "fork.knife"
            }
        }
    }

    @State private var half: Half = .workouts
    @State private var isShowingQuickActions = false
    @State private var quickAction: TrainingQuickAction?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    switcher(timeOfDay: timeOfDay)

                    switch half {
                    case .workouts: WorkoutsView()
                    case .food: FoodTrackingView()
                    }
                }

                if isShowingQuickActions {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .onTapGesture { closeQuickActions() }
                        .transition(.opacity)
                }

                quickActionMenu(timeOfDay: timeOfDay)
                    .padding(.trailing, RepbaseDesign.pageInset)
                    // Clear of the bottom bar, which floats over this tab
                    // rather than beside it: at 10 the button sat behind the
                    // bar with only its top corner showing. The bar is 46
                    // tall and sits 8 above the safe area, so this is that
                    // plus a gap.
                    .padding(.bottom, 64)
            }
            .homeTimeScreen(timeOfDay)
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isShowingQuickActions)
        }
        .onChange(of: half) { closeQuickActions() }
        .sheet(item: $quickAction) { action in
            quickActionDestination(action)
        }
    }

    private func switcher(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 3) {
            ForEach(Half.allCases) { item in
                Button {
                    half = item
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(item == half ? RepbasePalette.cream : timeOfDay.canvasSecondaryText)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if item == half {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(RepbaseDesign.ink)
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
        .padding(.horizontal, RepbaseDesign.pageInset)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.18), value: half)
    }

    private func quickActionMenu(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            if isShowingQuickActions {
                ForEach(actions) { action in
                    Button {
                        quickAction = action
                        closeQuickActions()
                    } label: {
                        Image(systemName: action.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(timeOfDay.accent)
                            .frame(width: 48, height: 48)
                            .repbaseDepthSurface(cornerRadius: 15)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.title)
                    .accessibilityHint(action.detail)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            Button {
                isShowingQuickActions.toggle()
            } label: {
                Image(systemName: isShowingQuickActions ? "xmark" : "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(RepbasePalette.cream)
                    .frame(width: 56, height: 56)
                    .background(RepbaseDesign.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.2), radius: 14, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isShowingQuickActions ? "Close quick actions" : "Open quick actions")
        }
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

    private func closeQuickActions() {
        isShowingQuickActions = false
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
