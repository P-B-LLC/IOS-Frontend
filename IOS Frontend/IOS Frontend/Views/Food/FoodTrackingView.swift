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
                dailySummary
                    .padding(.leading, 12)
                    .repbaseFeatureRail(RepbaseDesign.success, inset: 4)

                if let message = store.errorMessage {
                    syncNotice(message, timeOfDay: timeOfDay)
                } else if !store.isConnected {
                    syncNotice(
                        "Sign in to log food. Meals are kept on your account, not on this phone.",
                        timeOfDay: timeOfDay
                    )
                }

                mealsSection(timeOfDay: timeOfDay)
                    .padding(.leading, 12)
                    .repbaseFeatureRail(timeOfDay.accent, inset: 3)
                nutritionBreakdownLink(timeOfDay: timeOfDay)
                    .padding(.leading, 12)
                    .repbaseFeatureRail(RepbaseDesign.warning, inset: 3)
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 16)
            .padding(.bottom, RepbaseDesign.quickActionClearance)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .homeTimeScreen(timeOfDay)
    }

    private func foodHeader(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .accessibilityLabel("Back")
            }
            .buttonStyle(RepbaseSculptedIconButtonStyle(timeOfDay: timeOfDay))

            VStack(alignment: .leading, spacing: 3) {
                Text("NUTRITION")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.35)
                    .foregroundStyle(timeOfDay.accent)
                Text("Food logging")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.35)
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
            }

            Spacer(minLength: 0)

            Button {
                isEditingGoals = true
            } label: {
                Label("Goals", systemImage: "scope")
            }
            .buttonStyle(RepbaseAccentCapsuleButtonStyle(timeOfDay: timeOfDay))
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
                            .font(.subheadline.weight(.bold))
                        if Calendar.current.isDateInToday(selectedDate) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
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
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "calendar")
                            .font(.caption2.weight(.bold))
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
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(timeOfDay.secondaryText)

                            Text(date.formatted(.dateTime.day()))
                                .font(.caption.weight(.bold).monospacedDigit())
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

    private var dailySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            CalorieGoalCard(
                value: total.calories,
                goal: store.goals.calories,
                loggedFoodCount: loggedFoodCount
            )

            HStack(spacing: 8) {
                MacroGoalCard(title: "Protein", value: total.proteinGrams, goal: store.goals.proteinGrams)
                MacroGoalCard(title: "Carbs", value: total.carbohydrateGrams, goal: store.goals.carbohydrateGrams)
                MacroGoalCard(title: "Fat", value: total.fatGrams, goal: store.goals.fatGrams)
            }
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
        .font(.caption)
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
                Text("Today’s meals")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                Spacer()
                Text("\(total.calories.nutritionText) kcal")
                    .font(.caption.weight(.semibold))
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
            .repbaseCard(contentPadding: 10, cornerRadius: RepbaseDesign.cardRadius)

            HStack(spacing: 9) {
                Button {
                    isShowingSavedMeals = true
                } label: {
                    Label("Saved foods", systemImage: "bookmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .repbaseControlSurface(cornerRadius: 15)

                Button {
                    store.addMeal(on: selectedDate)
                } label: {
                    Label("Add meal", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
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
                        .font(.subheadline.weight(.semibold))
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
                    .font(.title3)
                    .foregroundStyle(timeOfDay.accent)
                Text("Nutrition breakdown")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.bold))
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
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DAILY ENERGY")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(phase.secondaryText)
                    Text("Calorie balance")
                        .font(.headline)
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(phase.usesDarkAppearance ? RepbasePalette.cream : RepbaseDesign.ink)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.045), in: Circle())
            }

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [phase.surfaceStart, phase.surfaceEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: phase.shadow, radius: 16, x: 0, y: 10)
                    .shadow(
                        color: Color.white.opacity(phase.usesDarkAppearance ? 0.04 : 0.9),
                        radius: 3,
                        x: 0,
                        y: -2
                    )

                ForEach(0..<48, id: \.self) { index in
                    Capsule()
                        .fill(index == progressTick ? RepbaseDesign.accent : phase.primaryText.opacity(index.isMultiple(of: 4) ? 0.62 : 0.22))
                        .frame(width: index.isMultiple(of: 4) ? 2 : 1, height: index.isMultiple(of: 4) ? 9 : 5)
                        .offset(y: -87)
                        .rotationEffect(.degrees(Double(index) * 7.5))
                }

                Circle()
                    .stroke(phase.primaryText.opacity(0.06), lineWidth: 16)
                    .frame(width: 142, height: 142)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        phase.usesDarkAppearance ? RepbasePalette.cream : RepbaseDesign.ink,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 142, height: 142)

                VStack(spacing: 3) {
                    Text(value.nutritionText)
                        .font(.system(size: 35, weight: .medium, design: .rounded))
                        .minimumScaleFactor(0.65)
                    Text("KCAL")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(phase.secondaryText)
                }
                .padding(15)
            }
            .frame(width: 196, height: 196)

            HStack(spacing: 0) {
                dialStat(title: "Remaining", value: remaining.nutritionText)
                Divider().frame(height: 35)
                dialStat(title: "Daily goal", value: goal.nutritionText)
                Divider().frame(height: 35)
                dialStat(title: "Foods", value: "\(loggedFoodCount)")
            }
        }
        .repbaseCard(contentPadding: 18, cornerRadius: RepbaseDesign.featureRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories, \(value.nutritionText) of \(goal.nutritionText), \(remaining.nutritionText) remaining")
    }

    private var remaining: Decimal { max(goal - value, 0) }

    private var progress: CGFloat {
        guard goal > 0 else { return 0 }
        return min(max(value.nutritionDouble / goal.nutritionDouble, 0), 1)
    }

    private var progressTick: Int {
        min(Int((progress * 47).rounded()), 47)
    }

    private func dialStat(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(phase.secondaryText)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MacroGoalCard: View {
    @Environment(\.workoutVisualPhase) private var phase
    let title: String
    let value: Decimal
    let goal: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(phase.secondaryText)
            Text("\(value.nutritionText) / \(goal.nutritionText)g")
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(phase.accent.opacity(0.12))
                    Capsule().fill(phase.accent).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .repbaseCard(contentPadding: 12, cornerRadius: 17)
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(phase.accent)
                .frame(width: 38, height: 38)
                .background(phase.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(meal.name)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(phase.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: isLogged ? "checkmark" : "plus")
                .font(.caption.weight(.bold))
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
