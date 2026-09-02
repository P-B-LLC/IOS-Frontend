//
//  FoodTrackingView.swift
//  IOS Frontend
//
//  Time-aware daily nutrition dashboard.
//

import SwiftUI

struct FoodTrackingView: View {
    /// Drawn when this was pushed onto somebody else's stack rather than
    /// opened as its own tab.
    ///
    /// This page hides the navigation bar, which is right when it is the
    /// root of the Food tab and wrong the moment it is pushed: Home links
    /// straight here to log food, and with no bar, no back button and a tab
    /// bar still pointing at Home -- correctly, since that is the stack you
    /// are on -- there was no way back out of it. Same flag and same reason
    /// as PlannerView, which Home also links to.
    var showsBackButton = false

    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDate = Date()
    @State private var isEditingGoals = false
    @State private var isShowingSavedMeals = false
    /// The month grid, opened from the week range.
    @State private var isShowingMonth = false
    /// Opens the composer on this page's own kind, so it asks which meal
    /// rather than which feature.
    @State private var isSharingMeal = false
    @State private var displayedNutrition: NutritionAmount?
    @State private var displayedLoggedMealCount: Int?
    @State private var recentlyLoggedMealID: FoodMeal.ID?
    @State private var nutritionPulse = false
    @State private var dayCompletionPulse = false
    @State private var mealSuccessMessage: String?
    @State private var lastHandledMealLogID: UUID?
    @State private var mealFeedbackTask: Task<Void, Never>?
    @State private var isFoodVisible = false

    var body: some View {
        screen(timeOfDay: HomeTimeOfDay.current)
        .fullScreenCover(isPresented: $isEditingGoals) {
            NutritionGoalsView()
        }
        .fullScreenCover(isPresented: $isShowingSavedMeals) {
            NavigationStack {
                SavedMealsView(referenceDate: selectedDate)
            }
        }
        .fullScreenCover(isPresented: $isSharingMeal) {
            PostComposerView(source: .meal)
        }
        .fullScreenCover(isPresented: $isShowingMonth) {
            NavigationStack {
                FoodMonthView(selectedDate: $selectedDate)
            }
        }
        .task {
            // The day being looked at has to exist on the server before
            // anything can be logged into it. onChange alone never fires for
            // the day the screen opens on.
            store.ensureDay(selectedDate)
        }
        .onAppear {
            isFoodVisible = true
            synchronizeDisplayedNutrition()
            presentLatestMealLogIfNeeded()
        }
        .onDisappear {
            isFoodVisible = false
            mealFeedbackTask?.cancel()
            mealFeedbackTask = nil
        }
        .onChange(of: selectedDate) {
            store.ensureDay(selectedDate)
            mealFeedbackTask?.cancel()
            nutritionPulse = false
            dayCompletionPulse = false
            recentlyLoggedMealID = nil
            mealSuccessMessage = nil
            synchronizeDisplayedNutrition()
            presentLatestMealLogIfNeeded()
        }
        .onChange(of: store.latestMealLogEvent?.id) { _, _ in
            guard isFoodVisible else { return }
            presentLatestMealLogIfNeeded()
        }
        .onChange(of: store.total(on: selectedDate)) { _, newTotal in
            guard mealFeedbackTask == nil else { return }
            displayedNutrition = newTotal
        }
        .onChange(of: store.loggedMealCount(on: selectedDate)) { _, newCount in
            guard mealFeedbackTask == nil else { return }
            displayedLoggedMealCount = newCount
        }
    }

    private func screen(timeOfDay: HomeTimeOfDay) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if showsBackButton {
                    HStack {
                        RytivoBrandLockup(size: 24)
                        Spacer()
                        Text("Food")
                            .font(.community(.title3, weight: .bold))
                            .foregroundStyle(timeOfDay.canvasPrimaryText)
                    }
                }
                foodHeader(timeOfDay: timeOfDay)
                weekSelector(timeOfDay: timeOfDay)
                dailySummary(timeOfDay: timeOfDay)

                if let message = store.errorMessage {
                    syncNotice(message, timeOfDay: timeOfDay)
                } else if !store.isConnected {
                    syncNotice(
                        "Sign in to log food. Meals are kept on your account, not on this phone.",
                        timeOfDay: timeOfDay
                    )
                }

                mealsSection(timeOfDay: timeOfDay)
                nutritionBreakdownLink(timeOfDay: timeOfDay)
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 16)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .scrollIndicators(.hidden)
        .minimizesBottomBarOnScroll()
        .toolbar(.hidden, for: .navigationBar)
        .homeTimeScreen(timeOfDay)
        .overlay(alignment: .bottom) {
            if let mealSuccessMessage {
                FoodLogSuccessToast(message: mealSuccessMessage)
                    .padding(.horizontal, RepbaseDesign.pageInset)
                    .padding(.bottom, RepbaseDesign.bottomBarClearance - 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: recentlyLoggedMealID)
    }

    private func foodHeader(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            if showsBackButton {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.community(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(timeOfDay.canvasPrimaryText)
                .accessibilityLabel("Back")
                .padding(.trailing, 2)
                // The header aligns on its bottom edge, which would put the
                // chevron level with the third line of text rather than where
                // a back control is looked for.
                .frame(maxHeight: .infinity, alignment: .top)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(Calendar.current.isDateInToday(selectedDate) ? "TODAY" : "NUTRITION")
                    .font(.community(size: 9, weight: .bold))
                    .tracking(1.35)
                    .foregroundStyle(timeOfDay.accent)
                Button { isShowingMonth = true } label: {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.community(.title, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                }
                .buttonStyle(.plain)
                Text("Build the day one meal at a time.")
                    .font(.community(.subheadline))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }

            Spacer(minLength: 0)

            Button {
                isEditingGoals = true
            } label: {
                Text("Goals")
            }
            .font(.community(.caption, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(timeOfDay.accent)
            .accessibilityHint("Change calorie and macronutrient targets")
        }
        .padding(.bottom, 4)
    }

    private func weekSelector(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    selectedDate = Date()
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedDateTitle)
                            .font(.community(.subheadline, weight: .bold))
                        if Calendar.current.isDateInToday(selectedDate) {
                            Image(systemName: "location.fill")
                                .font(.community(.caption2))
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    changeWeek(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Previous week")

                // The range is the natural place to ask for a wider view: it
                // is already the thing on screen that names a span of days.
                Button {
                    isShowingMonth = true
                } label: {
                    HStack(spacing: 4) {
                        Text(weekRangeTitle)
                            .font(.community(.subheadline, weight: .medium))
                        Image(systemName: "calendar")
                            .font(.community(.caption2, weight: .bold))
                    }
                    .foregroundStyle(timeOfDay.secondaryText)
                    .frame(minWidth: 90)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open the month, \(weekRangeTitle)")

                Button {
                    changeWeek(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Next week")
            }

            HStack(spacing: 0) {
                ForEach(weekDates, id: \.self) { date in
                    Button {
                        selectedDate = date
                    } label: {
                        VStack(spacing: 6) {
                            Text(date.formatted(.dateTime.weekday(.narrow)))
                                .font(.community(.caption2, weight: .semibold))
                                .foregroundStyle(timeOfDay.secondaryText)

                            Text(date.formatted(.dateTime.day()))
                                .font(.community(.caption, weight: .bold).monospacedDigit())
                                .foregroundStyle(isSelected(date) ? RepbasePalette.cream : timeOfDay.primaryText)
                                .frame(width: 30, height: 28)
                                .background(
                                    isSelected(date) ? timeOfDay.accent : Color.clear,
                                    in: Capsule()
                                )
                                .scaleEffect(
                                    isSelected(date) && dayCompletionPulse && !reduceMotion
                                        ? 1.10
                                        : 1
                                )
                                .shadow(
                                    color: isSelected(date) && dayCompletionPulse
                                        ? timeOfDay.accent.opacity(0.30)
                                        : Color.clear,
                                    radius: 9
                                )
                                .animation(
                                    .spring(response: 0.48, dampingFraction: 0.62),
                                    value: dayCompletionPulse
                                )
                                .overlay(alignment: .bottomTrailing) {
                                    if store.hasLoggedFood(on: date), !isSelected(date) {
                                        Circle()
                                            .fill(timeOfDay.accent)
                                            .frame(width: 5, height: 5)
                                            .offset(x: 1, y: 1)
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                    .accessibilityValue(isSelected(date) ? "Selected" : "")
                }
            }
        }
        .repbaseCard(contentPadding: 13, cornerRadius: RepbaseDesign.cardRadius)
        // Anywhere that is not already a control opens the month. The buttons
        // inside — a day, the week arrows, Today — take their own taps first,
        // so this only catches the gaps between them.
        .contentShape(Rectangle())
        .onTapGesture { isShowingMonth = true }
    }

    private func dailySummary(timeOfDay: HomeTimeOfDay) -> some View {
        let shown = displayedNutrition ?? total

        return VStack(alignment: .leading, spacing: 10) {
            CalorieGoalCard(
                value: shown.calories,
                goal: store.goals.calories,
                loggedFoodCount: loggedFoodCount,
                isPulsing: nutritionPulse,
                isDayComplete: selectedDayIsFullyLogged
            )

            HStack(spacing: 12) {
                MacroGoalCard(title: "Protein", value: shown.proteinGrams, goal: store.goals.proteinGrams, color: Color(hex: 0xD9824B), isPulsing: nutritionPulse, delay: 0.05)
                MacroGoalCard(title: "Carbs", value: shown.carbohydrateGrams, goal: store.goals.carbohydrateGrams, color: Color(hex: 0x4AAFB3), isPulsing: nutritionPulse, delay: 0.14)
                MacroGoalCard(title: "Fat", value: shown.fatGrams, goal: store.goals.fatGrams, color: Color(hex: 0xB76AA5), isPulsing: nutritionPulse, delay: 0.23)
            }
        }
        .padding(18)
        .foregroundStyle(timeOfDay.primaryText)
        .background(
            dayCompletionPulse
                ? LinearGradient(
                    colors: [
                        Color.repbaseDynamic(light: Color(hex: 0xFFFAF6), dark: Color(hex: 0x171817)),
                        Color.repbaseDynamic(light: Color(hex: 0xEEF8F1), dark: Color(hex: 0x17271E))
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                : LinearGradient(
                    colors: [timeOfDay.surfaceRaised, timeOfDay.surfaceRaised],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .strokeBorder(
                    dayCompletionPulse
                        ? Color.repbaseDynamic(
                            light: Color(hex: 0x4E7461).opacity(0.22),
                            dark: Color(hex: 0x9AC4AB).opacity(0.20)
                        )
                        : timeOfDay.border,
                    lineWidth: 1
                )
        }
        .overlay {
            if dayCompletionPulse && !reduceMotion {
                FoodSummarySheen()
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .offset(y: dayCompletionPulse && !reduceMotion ? -2 : 0)
        .shadow(
            color: dayCompletionPulse
                ? Color.repbaseDynamic(
                    light: Color(hex: 0x4E7461).opacity(0.13),
                    dark: Color(hex: 0x62A37B).opacity(0.13)
                )
                : Color.clear,
            radius: 17,
            y: 8
        )
        .animation(
            .spring(response: 0.56, dampingFraction: 0.76),
            value: dayCompletionPulse
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily nutrition totals")
    }

    /// Shown only when what is on screen is not what the server holds.
    private func syncNotice(_ message: String, timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "icloud.slash")
                .foregroundStyle(timeOfDay.accent)
            Text(message)
            Spacer(minLength: 0)
        }
        .font(.community(.caption))
        .foregroundStyle(timeOfDay.canvasSecondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(timeOfDay.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private func mealsSection(timeOfDay: HomeTimeOfDay) -> some View {
        let meals = store.meals(on: selectedDate)
        // Every WorkoutVisualPhase token ignores which case it is and follows
        // the trait instead, so choosing .focus for dark stopped changing
        // anything the moment the colours became dynamic.
        let visualPhase: WorkoutVisualPhase = .prepare


        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MEALS")
                    .font(.community(.caption2, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                Spacer()
                Text("\(displayedLoggedMealCount ?? meals.filter { !$0.entries.isEmpty }.count) of \(meals.count) logged")
                    .font(.community(.caption, weight: .semibold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .contentTransition(.numericText())
            }

            VStack(spacing: 0) {
                ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                    NavigationLink {
                        MealDetailView(date: selectedDate, mealID: meal.id)
                    } label: {
                        MealRow(
                            meal: meal,
                            isRecentlyLogged: recentlyLoggedMealID == meal.id
                        )
                    }
                    .buttonStyle(.plain)

                    if index < meals.count - 1 {
                        Divider().opacity(0.55)
                    }
                }
            }
            .padding(.horizontal, 6)

            HStack(spacing: 9) {
                Button {
                    isShowingSavedMeals = true
                } label: {
                    Label("Saved foods", systemImage: "bookmark")
                        .font(.community(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .repbaseControlSurface(cornerRadius: 15)

                Button {
                    store.addMeal(on: selectedDate)
                } label: {
                    Label("Add meal", systemImage: "plus.circle")
                        .font(.community(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .repbaseControlSurface(cornerRadius: 15)
            }

            // Only on a day with nothing logged on it. Copying onto a day that
            // already has food is refused by the server rather than doubling
            // it, so there is nothing to gain by offering it there.
            if store.canCopyPreviousDay(onto: selectedDate) {
                Button {
                    store.copyPreviousDay(onto: selectedDate)
                } label: {
                    Label(copyPreviousDayTitle, systemImage: "clock.arrow.circlepath")
                        .font(.community(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .repbaseControlSurface(cornerRadius: 15)
                .disabled(store.isSaving)
            }

            if let firstMeal = meals.first {
                NavigationLink {
                    MealDetailView(date: selectedDate, mealID: firstMeal.id)
                } label: {
                    Label("Log Food", systemImage: "fork.knife")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WorkoutPrimaryButtonStyle(phase: visualPhase))
            }

            // Sharing belongs to the page that lists the meals, not to each
            // meal's own screen: from here the composer can ask which one, and
            // there is one place to look for it rather than four.
            //
            // Shown only once something has been eaten. A day with four empty
            // slots has nothing the API would accept.
            if meals.contains(where: { $0.serverID != nil && !$0.entries.isEmpty }) {
                Button {
                    isSharingMeal = true
                } label: {
                    Label("Share a meal", systemImage: "square.and.arrow.up")
                        .font(.community(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .repbaseControlSurface(cornerRadius: 15)
            }
        }
    }

    private func nutritionBreakdownLink(timeOfDay: HomeTimeOfDay) -> some View {
        NavigationLink {
            ScrollView {
                NutritionBreakdownView(meals: store.meals(on: selectedDate))
                    .padding()
                    // Pushed inside the tab, so the bottom bar overlays it.
                    .padding(.bottom, RepbaseDesign.bottomBarClearance)
            }
            .navigationTitle("Nutrition Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .homeTimeScreen(timeOfDay)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "chart.pie")
                    .font(.community(.title3))
                    .foregroundStyle(timeOfDay.accent)
                Text("Nutrition breakdown")
                    .font(.community(.headline))
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.community(.caption, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .repbaseCard(contentPadding: 14, cornerRadius: 17)
        }
        .buttonStyle(.plain)
    }

    /// Named for the day being looked at, not for today. The week strip can
    /// be moved off today, and "yesterday" would then be the wrong word for
    /// the day this copies.
    private var copyPreviousDayTitle: String {
        Calendar.current.isDateInToday(selectedDate)
            ? "Same as yesterday"
            : "Same as the day before"
    }

    private var total: NutritionAmount { store.total(on: selectedDate) }

    private var loggedFoodCount: Int {
        store.meals(on: selectedDate).reduce(0) { $0 + $1.entries.count }
    }

    private var selectedDayIsFullyLogged: Bool {
        let meals = store.meals(on: selectedDate)
        return !meals.isEmpty && meals.allSatisfy { !$0.entries.isEmpty }
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: selectedDate)
        let weekday = calendar.component(.weekday, from: day)
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: day) ?? day
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: sunday) }
    }

    private var selectedDateTitle: String {
        if Calendar.current.isDateInToday(selectedDate) { return "Today" }
        return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var weekRangeTitle: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "" }
        if Calendar.current.isDate(first, equalTo: last, toGranularity: .month) {
            return "\(first.formatted(.dateTime.month(.abbreviated).day()))–\(last.formatted(.dateTime.day()))"
        }
        return "\(first.formatted(.dateTime.month(.abbreviated).day()))–\(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func changeWeek(by amount: Int) {
        selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: amount, to: selectedDate) ?? selectedDate
    }

    private func synchronizeDisplayedNutrition() {
        displayedNutrition = store.total(on: selectedDate)
        displayedLoggedMealCount = store.loggedMealCount(on: selectedDate)
    }

    /// Replays the confirmed before/after nutrition when Food becomes visible.
    /// The event is intentionally not consumed here: Home still needs those
    /// snapshots if the user goes there next. Only a large celebration is
    /// marked as shown, preventing the same confetti from firing twice.
    private func presentLatestMealLogIfNeeded() {
        guard let event = store.latestMealLogEvent,
              event.id != lastHandledMealLogID,
              Calendar.current.isDate(event.date, inSameDayAs: selectedDate)
        else { return }

        lastHandledMealLogID = event.id
        mealFeedbackTask?.cancel()
        displayedNutrition = event.before
        displayedLoggedMealCount = event.beforeMealCount
        recentlyLoggedMealID = nil
        nutritionPulse = false
        dayCompletionPulse = false

        let meals = store.meals(on: selectedDate)
        let mealName = meals.first(where: { $0.id == event.mealID })?.name ?? "Meal"
        let completedMeal = event.afterMealCount > event.beforeMealCount
        let completedDay = !meals.isEmpty
            && event.beforeMealCount < meals.count
            && event.afterMealCount == meals.count

        mealFeedbackTask = Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard !Task.isCancelled else { return }

            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.18)
                    : .spring(response: 0.72, dampingFraction: 0.84)
            ) {
                displayedNutrition = event.after
                displayedLoggedMealCount = event.afterMealCount
                recentlyLoggedMealID = event.mealID
                nutritionPulse = true
                dayCompletionPulse = completedDay
                mealSuccessMessage = completedDay
                    ? "Day complete. Every meal is in."
                    : completedMeal ? "\(mealName) logged" : "\(mealName) updated"
            }

            if completedDay && event.shouldCelebrate {
                store.markMealLogCelebrated(event.id)
                RepbaseCelebrations.show(.mealLogged)
            }

            try? await Task.sleep(for: .milliseconds(reduceMotion ? 260 : 1_650))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.24)) {
                recentlyLoggedMealID = nil
                nutritionPulse = false
                mealSuccessMessage = nil
            }

            if dayCompletionPulse {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 620))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.26)) {
                    dayCompletionPulse = false
                }
            }
            mealFeedbackTask = nil
        }
    }
}

private struct CalorieGoalCard: View {
    @Environment(\.workoutVisualPhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Decimal
    let goal: Decimal
    let loggedFoodCount: Int
    let isPulsing: Bool
    let isDayComplete: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DAILY NUTRITION")
                        .font(.community(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(phase.secondaryText)
                }
                Spacer()
                if isDayComplete {
                    Text("DAY COMPLETE")
                        .font(.community(size: 8, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(
                            Color.repbaseDynamic(
                                light: Color(hex: 0x406D55),
                                dark: Color(hex: 0xB9DEC7)
                            )
                        )
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Color.repbaseDynamic(
                                light: Color(hex: 0xE4F1E8),
                                dark: Color(hex: 0x213A2C)
                            ),
                            in: Capsule()
                        )
                        .transition(.scale.combined(with: .opacity))
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(value.nutritionText)
                    .font(.community(size: 36, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .scaleEffect(isPulsing && !reduceMotion ? 1.025 : 1, anchor: .leading)
                    .animation(
                        .spring(response: 0.48, dampingFraction: 0.68),
                        value: isPulsing
                    )
                Text("OF \(goal.nutritionText) KCAL")
                    .font(.community(.caption2, weight: .bold))
                    .foregroundStyle(phase.secondaryText)
            }

            Text("\(remaining.nutritionText) kcal remaining")
                .font(.community(.subheadline, weight: .semibold))
                .foregroundStyle(phase.accent)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(phase.secondaryText.opacity(0.20))
                    Capsule().fill(phase.accent)
                        .frame(width: proxy.size.width * progress)
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.18)
                                : .spring(response: 0.72, dampingFraction: 0.84),
                            value: progress
                        )
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories, \(value.nutritionText) of \(goal.nutritionText), \(remaining.nutritionText) remaining")
    }

    private var remaining: Decimal { max(goal - value, 0) }

    private var progress: CGFloat {
        guard goal > 0 else { return 0 }
        return min(max(value.nutritionDouble / goal.nutritionDouble, 0), 1)
    }

}

private struct MacroGoalCard: View {
    @Environment(\.workoutVisualPhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let value: Decimal
    let goal: Decimal
    let color: Color
    let isPulsing: Bool
    let delay: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.community(.caption, weight: .medium))
                .foregroundStyle(phase.secondaryText)
            Text("\(value.nutritionText) / \(goal.nutritionText)g")
                .font(.community(.subheadline, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(phase.secondaryText.opacity(0.18))
                    Capsule().fill(color).frame(width: proxy.size.width * progress)
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.18)
                                : .spring(response: 0.68, dampingFraction: 0.82).delay(delay),
                            value: progress
                        )
                }
            }
            .frame(height: 5)
            .overlay {
                if isPulsing && !reduceMotion {
                    MacroRailSheen(color: color, delay: delay)
                        .clipShape(Capsule())
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value.nutritionText) of \(goal.nutritionText) grams")
    }

    private var progress: CGFloat {
        guard goal > 0 else { return 0 }
        return min(max(value.nutritionDouble / goal.nutritionDouble, 0), 1)
    }
}

private struct MealRow: View {
    @Environment(\.workoutVisualPhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let meal: FoodMeal
    let isRecentlyLogged: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: mealSymbol)
                .font(.community(.subheadline, weight: .semibold))
                .foregroundStyle(phase.accent)
                .frame(width: 38, height: 38)
                .background(phase.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(meal.name)
                    .font(.community(.subheadline, weight: .semibold))
                Text(subtitle)
                    .font(.community(.caption))
                    .foregroundStyle(phase.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: isLogged ? "checkmark" : "plus")
                .font(.community(.caption, weight: .bold))
                .foregroundStyle(isLogged ? RepbasePalette.cream : phase.accent)
                .frame(width: 29, height: 29)
                .background(isLogged ? Color(hex: 0x5DAA86) : phase.accent.opacity(0.10), in: Circle())
                .scaleEffect(isRecentlyLogged && !reduceMotion ? 1.10 : 1)
                .animation(
                    .spring(response: 0.46, dampingFraction: 0.62),
                    value: isRecentlyLogged
                )
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 10)
        .background {
            if isRecentlyLogged {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        Color.repbaseDynamic(
                            light: Color(hex: 0xEEF8F1),
                            dark: Color(hex: 0x17271E)
                        )
                    )
                    .transition(.opacity)
            }
        }
        .offset(y: isRecentlyLogged && !reduceMotion ? -2 : 0)
        .shadow(
            color: isRecentlyLogged
                ? RepbaseDesign.success.opacity(0.14)
                : Color.clear,
            radius: 11,
            y: 5
        )
        .animation(
            .spring(response: 0.52, dampingFraction: 0.74),
            value: isRecentlyLogged
        )
        .contentShape(Rectangle())
    }

    private var isLogged: Bool { !meal.entries.isEmpty }

    private var subtitle: String {
        guard !meal.entries.isEmpty else { return "Nothing logged yet" }
        return "\(meal.entries.map(\.name).joined(separator: ", ")) · \(meal.totalNutrition.calories.nutritionText) kcal"
    }

    private var mealSymbol: String {
        let name = meal.name.lowercased()
        if name.contains("breakfast") || name.contains("1") { return "sun.max" }
        if name.contains("lunch") || name.contains("2") { return "sun.haze" }
        if name.contains("dinner") || name.contains("3") { return "takeoutbag.and.cup.and.straw" }
        if name.contains("snack") || name.contains("4") { return "moon" }
        return "fork.knife"
    }
}

private struct FoodLogSuccessToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .foregroundStyle(
                    Color.repbaseDynamic(
                        light: Color(hex: 0x4E7461),
                        dark: Color(hex: 0x9AC4AB)
                    )
                )
            Text(message)
                .font(.community(.footnote, weight: .semibold))
                .foregroundStyle(
                    Color.repbaseDynamic(
                        light: RepbasePalette.espresso,
                        dark: Color.white
                    )
                )
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 48)
        .background(
            Color.repbaseDynamic(
                light: Color(hex: 0xF1F8F3),
                dark: Color(hex: 0x1D3126)
            ),
            in: Capsule()
        )
        .overlay {
            Capsule().strokeBorder(
                Color.repbaseDynamic(
                    light: Color(hex: 0x4E7461).opacity(0.15),
                    dark: Color(hex: 0x9AC4AB).opacity(0.18)
                ),
                lineWidth: 1
            )
        }
        .shadow(color: Color.black.opacity(0.17), radius: 18, x: 0, y: 8)
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct FoodSummarySheen: View {
    @State private var travel: CGFloat = -1.2

    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.42), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geometry.size.width * 0.38)
            .rotationEffect(.degrees(-15))
            .offset(x: geometry.size.width * travel)
        }
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.82).delay(0.12)) {
                travel = 2.7
            }
        }
    }
}

private struct MacroRailSheen: View {
    let color: Color
    let delay: Double
    @State private var travel: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.clear, color.opacity(0.70), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: geometry.size.width * 0.34)
                .offset(x: geometry.size.width * travel)
        }
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.70).delay(delay)) {
                travel = 2.9
            }
        }
    }
}

extension View {
    func foodCard() -> some View {
        repbaseCard(contentPadding: 12, cornerRadius: 16)
    }
}

#Preview {
    NavigationStack { FoodTrackingView() }
        .environment(FoodTrackingStore.preview)
}
