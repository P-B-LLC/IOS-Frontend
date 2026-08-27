//
//  FoodTrackingView.swift
//  IOS Frontend
//
//  Time-aware daily nutrition dashboard.
//

import SwiftUI

struct FoodTrackingView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var isEditingGoals = false
    @State private var isShowingSavedMeals = false
    /// The month grid, opened from the week range.
    @State private var isShowingMonth = false
    /// Opens the composer on this page's own kind, so it asks which meal
    /// rather than which feature.
    @State private var isSharingMeal = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            screen(timeOfDay: HomeTimeOfDay(date: context.date))
        }
        .sheet(isPresented: $isEditingGoals) {
            NutritionGoalsView()
        }
        .sheet(isPresented: $isShowingSavedMeals) {
            NavigationStack {
                SavedMealsView(referenceDate: selectedDate)
            }
        }
        .sheet(isPresented: $isSharingMeal) {
            PostComposerView(source: .meal)
        }
        .sheet(isPresented: $isShowingMonth) {
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
        .onChange(of: selectedDate) {
            store.ensureDay(selectedDate)
        }
    }

    private func screen(timeOfDay: HomeTimeOfDay) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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
        .toolbar(.hidden, for: .navigationBar)
        .homeTimeScreen(timeOfDay)
    }

    private func foodHeader(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
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
        VStack(alignment: .leading, spacing: 10) {
            CalorieGoalCard(
                value: total.calories,
                goal: store.goals.calories,
                loggedFoodCount: loggedFoodCount
            )

            HStack(spacing: 12) {
                MacroGoalCard(title: "Protein", value: total.proteinGrams, goal: store.goals.proteinGrams, color: Color(hex: 0xD9824B))
                MacroGoalCard(title: "Carbs", value: total.carbohydrateGrams, goal: store.goals.carbohydrateGrams, color: Color(hex: 0x4AAFB3))
                MacroGoalCard(title: "Fat", value: total.fatGrams, goal: store.goals.fatGrams, color: Color(hex: 0xB76AA5))
            }
        }
        .padding(18)
        .foregroundStyle(timeOfDay.primaryText)
        .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .strokeBorder(timeOfDay.border, lineWidth: 1)
        }
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
        let visualPhase: WorkoutVisualPhase = timeOfDay.usesDarkAppearance ? .focus : .prepare

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MEALS")
                    .font(.community(.caption2, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                Spacer()
                Text("\(meals.filter { !$0.entries.isEmpty }.count) of \(meals.count) logged")
                    .font(.community(.caption, weight: .semibold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }

            VStack(spacing: 0) {
                ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                    NavigationLink {
                        MealDetailView(date: selectedDate, mealID: meal.id)
                    } label: {
                        MealRow(meal: meal)
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

    private var total: NutritionAmount { store.total(on: selectedDate) }

    private var loggedFoodCount: Int {
        store.meals(on: selectedDate).reduce(0) { $0 + $1.entries.count }
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
}

private struct CalorieGoalCard: View {
    @Environment(\.workoutVisualPhase) private var phase
    let value: Decimal
    let goal: Decimal
    let loggedFoodCount: Int

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
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(value.nutritionText)
                    .font(.community(size: 36, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
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
    let title: String
    let value: Decimal
    let goal: Decimal
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.community(.caption, weight: .medium))
                .foregroundStyle(phase.secondaryText)
            Text("\(value.nutritionText) / \(goal.nutritionText)g")
                .font(.community(.subheadline, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(phase.secondaryText.opacity(0.18))
                    Capsule().fill(color).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 5)
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
    let meal: FoodMeal

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
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 10)
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

extension View {
    func foodCard() -> some View {
        repbaseCard(contentPadding: 12, cornerRadius: 16)
    }
}

#Preview {
    NavigationStack { FoodTrackingView() }
        .environment(FoodTrackingStore.preview)
}
