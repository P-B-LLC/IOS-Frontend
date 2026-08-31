//
//  FoodTrackingStore.swift
//  IOS Frontend
//
//  Backend-backed food logging. Every meal, food, recipe and goal on these
//  screens is a row on the server; nothing is kept only on the phone.
//

import Foundation
import Observation

@MainActor
@Observable
final class FoodTrackingStore {
    nonisolated struct MealLogEvent: Equatable, Sendable {
        let id: UUID
        let date: Date
        let mealID: FoodMeal.ID
        let before: NutritionAmount
        let after: NutritionAmount
        let beforeMealCount: Int
        let afterMealCount: Int
        var shouldCelebrate: Bool
    }

    private var repository: FoodAPIRepository?
    /// Built beside the food repository and from the same credentials. The
    /// picker used to make its own and point it at a third party; a screen
    /// holding its own API client is how that went unnoticed.
    private var catalogue: FoodDatabaseRepository?
    private var connectionGeneration = UUID()
    /// Days a screen asked for before there was a server to ask.
    private var pendingDays: Set<String> = []

    /// Meals by `YYYY-MM-DD`, exactly as the server groups them.
    private(set) var days: [String: [FoodMeal]] = [:]
    private(set) var savedMeals: [SavedFoodMeal] = []
    private(set) var recentFoods: [FoodEntry] = []
    private(set) var goals: NutritionGoals = .default
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    /// A successful server write Home can consume once when it becomes visible.
    /// The snapshots let Home animate from the last confirmed value even when
    /// Food dismissed before the request itself finished.
    private(set) var latestMealLogEvent: MealLogEvent?

    var isConnected: Bool { repository != nil }

    init() {}

    // MARK: - Reading

    func meals(on date: Date) -> [FoodMeal] {
        days[dateKey(for: date)] ?? []
    }

    func total(on date: Date) -> NutritionAmount {
        meals(on: date).reduce(.zero) { $0 + $1.totalNutrition }
    }

    func loggedMealCount(on date: Date) -> Int {
        meals(on: date).filter { !$0.entries.isEmpty }.count
    }

    func consumeLatestMealLog(on date: Date) -> MealLogEvent? {
        guard let event = latestMealLogEvent,
              Calendar.current.isDate(event.date, inSameDayAs: date) else {
            return nil
        }
        latestMealLogEvent = nil
        return event
    }

    /// Food may already have presented the large completion burst before Home
    /// becomes visible. The before/after event is still left for Home to
    /// animate, but its confetti is suppressed so one meal never celebrates
    /// twice merely because the user changed tabs.
    func markMealLogCelebrated(_ id: UUID) {
        guard latestMealLogEvent?.id == id else { return }
        latestMealLogEvent?.shouldCelebrate = false
    }

    func hasLoggedFood(on date: Date) -> Bool {
        meals(on: date).contains { !$0.entries.isEmpty }
    }

    // MARK: - The server

    func connect(configuration: APIConfiguration, token: String) async {
        let generation = UUID()
        connectionGeneration = generation
        isLoading = true
        errorMessage = nil
        defer { if connectionGeneration == generation { isLoading = false } }

        do {
            catalogue = try FoodDatabaseRepository(
                configuration: configuration,
                token: token
            )
            let repository = try FoodAPIRepository(
                configuration: configuration,
                token: token
            )
            self.repository = repository

            let today = Date()
            // A fortnight back and a week forward, not a month either way.
            // Sixty-two days of meals were read on every sign-in to draw one,
            // and any day outside this window is fetched by `ensureDay` the
            // moment a screen asks for it. Backwards is wider than forwards
            // because meals are logged after eating; the forward days are for
            // meal prep, which is planned a week out rather than a month.
            let loaded = try await repository.days(
                from: dateKey(for: today.addingTimeInterval(-14 * 86_400)),
                to: dateKey(for: today.addingTimeInterval(7 * 86_400))
            )
            // Started together rather than awaited one after another. These
            // four reads do not depend on each other, and run sequentially they
            // cost four round-trips of latency to show one screen.
            async let recipesRequest = repository.savedMeals()
            async let targetsRequest = repository.goals()
            async let recentRequest = repository.recentFoods()
            let (recipes, targets, recent) = try await (
                recipesRequest,
                targetsRequest,
                recentRequest
            )

            guard connectionGeneration == generation else { return }
            days = loaded
            savedMeals = recipes
            goals = targets
            recentFoods = recent

            // Whatever was on screen while this was still connecting. Only
            // days something actually asked for: laying slots down on every
            // day a widget merely summarised would write four rows a day for
            // people who never open Food.
            let waiting = pendingDays
            pendingDays = []
            for key in waiting {
                openDay(key, using: repository)
            }
        } catch {
            guard connectionGeneration == generation else { return }
            repository = nil
            errorMessage = error.userFacingMessage
        }
    }

    func disconnect() {
        connectionGeneration = UUID()
        repository = nil
        pendingDays = []
        days = [:]
        // One user's month must never be shown to the next, and a month marked
        // loaded would stop the new account's from being read at all.
        loadedMonths = []
        isLoadingMonth = false
        savedMeals = []
        recentFoods = []
        goals = .default
        isLoading = false
        isSaving = false
        errorMessage = nil
        latestMealLogEvent = nil
    }

    /// Signing out. Named `reset` because that is what the app calls it.
    func reset() {
        disconnect()
    }

    // MARK: - Days

    /// Opens a day, laying down its empty meal slots the first time.
    ///
    /// The slots are the server's, not four the app draws while it waits: a
    /// meal the app invented has no id, and the first food logged into it would
    /// have nowhere to go.
    /// Months already asked for, so opening the month view twice does not ask
    /// twice and flicking back and forth does not re-read what is in hand.
    private var loadedMonths: Set<String> = []
    private(set) var isLoadingMonth = false

    /// Reads a whole month in one request.
    ///
    /// Not thirty calls to `ensureDay`. The month grid wants every day at
    /// once, and the range endpoint already exists for exactly this; asking
    /// per day would be thirty round trips to fill one screen.
    func ensureMonth(_ date: Date) async {
        guard let repository else { return }
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: date) else { return }

        let key = dateKey(for: month.start)
        guard !loadedMonths.contains(key) else { return }

        let generation = connectionGeneration
        isLoadingMonth = true
        defer { if connectionGeneration == generation { isLoadingMonth = false } }

        do {
            let loaded = try await repository.days(
                from: dateKey(for: month.start),
                // `end` is inclusive on the server and `month.end` is the
                // first instant of the next month, so step back a day rather
                // than reading one that belongs to the month after.
                to: dateKey(for: month.end.addingTimeInterval(-86_400))
            )
            guard connectionGeneration == generation else { return }
            // Merged, not replaced: days already open elsewhere keep whatever
            // was just logged into them.
            days.merge(loaded) { _, fresh in fresh }
            loadedMonths.insert(key)
        } catch {
            report(error, generation: generation)
        }
    }

    func ensureDay(_ date: Date) {
        let key = dateKey(for: date)
        guard let repository else {
            // Asked for before signing in finished. Remembered rather than
            // dropped: a screen asks for its day once, when it appears, and a
            // silent return would leave that day with no slots to log into
            // until something else happened to move the date.
            pendingDays.insert(key)
            return
        }
        openDay(key, using: repository)
    }

    private func openDay(_ key: String, using repository: FoodAPIRepository) {
        let generation = connectionGeneration
        Task {
            do {
                let meals = try await repository.openDay(key)
                guard connectionGeneration == generation else { return }
                days[key] = meals
            } catch {
                report(error, generation: generation)
            }
        }
    }

    // MARK: - Meals

    func addMeal(on date: Date) {
        let key = dateKey(for: date)
        let next = (days[key]?.count ?? 0) + 1
        perform(on: date) { repository in
            try await repository.addMeal(named: "Meal \(next)", on: key)
        } merge: { meals, added in
            meals.append(added)
        }
    }

    func renameMeal(id: FoodMeal.ID, to name: String, on date: Date) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let serverID = mealServerID(id, on: date) else { return }
        perform(on: date) { repository in
            try await repository.renameMeal(serverID, to: name)
        } merge: { meals, renamed in
            Self.replace(renamed, in: &meals)
        }
    }

    func removeMeal(id: FoodMeal.ID, on date: Date) {
        guard let serverID = mealServerID(id, on: date) else { return }
        perform(on: date) { repository in
            try await repository.deleteMeal(serverID)
        } merge: { meals, _ in
            meals.removeAll { $0.serverID == serverID }
        }
    }

    // MARK: - Foods

    func saveFood(
        _ food: FoodEntry,
        in mealID: FoodMeal.ID,
        on date: Date,
        celebrates: Bool = true
    ) {
        guard let serverID = mealServerID(mealID, on: date) else { return }
        let before = total(on: date)
        let beforeMealCount = loggedMealCount(on: date)
        perform(on: date) { repository in
            let saved = try await repository.saveFood(food, inMeal: serverID)
            return (saved, serverID)
        } merge: { meals, result in
            guard let index = meals.firstIndex(where: { $0.serverID == result.1 })
            else { return }
            if let existing = meals[index].entries
                .firstIndex(where: { $0.serverID == result.0.serverID }) {
                meals[index].entries[existing] = result.0
            } else {
                meals[index].entries.append(result.0)
            }
        } onSuccess: {
            self.latestMealLogEvent = MealLogEvent(
                id: UUID(),
                date: Calendar.current.startOfDay(for: date),
                mealID: mealID,
                before: before,
                after: self.total(on: date),
                beforeMealCount: beforeMealCount,
                afterMealCount: self.loggedMealCount(on: date),
                shouldCelebrate: celebrates
            )
        }
        refreshRecentFoods()
    }

    func removeFood(id: FoodEntry.ID, from mealID: FoodMeal.ID, on date: Date) {
        guard let mealServerID = mealServerID(mealID, on: date),
              let entryServerID = days[dateKey(for: date)]?
                .first(where: { $0.serverID == mealServerID })?
                .entries.first(where: { $0.id == id })?.serverID
        else { return }

        perform(on: date) { repository in
            try await repository.deleteFood(entryServerID)
        } merge: { meals, _ in
            guard let index = meals.firstIndex(where: { $0.serverID == mealServerID })
            else { return }
            meals[index].entries.removeAll { $0.serverID == entryServerID }
        }
    }

    // MARK: - Recipes

    func saveReusableMeal(_ savedMeal: SavedFoodMeal) {
        guard let repository else { return }
        let generation = connectionGeneration
        isSaving = true
        Task {
            defer { if connectionGeneration == generation { isSaving = false } }
            do {
                let saved = try await repository.saveRecipe(savedMeal)
                guard connectionGeneration == generation else { return }
                if let index = savedMeals.firstIndex(where: {
                    $0.serverID == saved.serverID
                }) {
                    savedMeals[index] = saved
                } else {
                    savedMeals.append(saved)
                }
                savedMeals.sort {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            } catch {
                report(error, generation: generation)
            }
        }
    }

    func removeReusableMeal(id: SavedFoodMeal.ID) {
        guard let repository,
              let serverID = savedMeals.first(where: { $0.id == id })?.serverID
        else { return }
        let generation = connectionGeneration
        Task {
            do {
                try await repository.deleteRecipe(serverID)
                guard connectionGeneration == generation else { return }
                savedMeals.removeAll { $0.serverID == serverID }
            } catch {
                report(error, generation: generation)
            }
        }
    }

    /// Copies a recipe into the same numbered meal on every date chosen.
    ///
    /// One request for the whole set: the server applies them in a transaction,
    /// so a week of meal prep either lands or does not, rather than leaving the
    /// app to work out which days went through.
    /// What applying a planned day actually managed to write.
    ///
    /// Each slot is its own request, so a plan can half-succeed. Saying "done"
    /// over a day that took two of four meals would be a lie the user only
    /// discovers by counting.
    nonisolated struct PlanOutcome: Sendable {
        var applied: [String] = []
        var failed: [String] = []
        var errorMessage: String?

        var isCompleteSuccess: Bool { failed.isEmpty && errorMessage == nil }
    }

    /// Writes a planned day: each saved meal into its own numbered slot.
    ///
    /// One request per slot, because the endpoint copies one recipe into one
    /// meal number across dates — there is no operation that takes a whole
    /// day's plan at once, so the loop is the contract's shape, not a choice.
    func applyPlan(
        _ slots: [(meal: SavedFoodMeal, number: Int)],
        to date: Date
    ) async -> PlanOutcome {
        guard let repository, !isSaving else {
            return PlanOutcome(errorMessage: "Not connected to Repbase.")
        }

        let generation = connectionGeneration
        let key = dateKey(for: date)
        isSaving = true
        defer { if connectionGeneration == generation { isSaving = false } }

        var outcome = PlanOutcome()
        for slot in slots {
            guard let serverID = slot.meal.serverID else {
                outcome.failed.append(slot.meal.name)
                continue
            }
            do {
                _ = try await repository.applyRecipe(
                    serverID,
                    toDates: [key],
                    mealNumber: slot.number
                )
                outcome.applied.append(slot.meal.name)
            } catch {
                outcome.failed.append(slot.meal.name)
                // The first failure's wording, not the last: later slots often
                // fail for the same reason and the first is the one that
                // explains it.
                if outcome.errorMessage == nil {
                    outcome.errorMessage = error.userFacingMessage
                }
            }
        }

        guard connectionGeneration == generation else { return outcome }
        // Read the day back rather than assuming what landed. Some slots may
        // have been written and some not, and the server knows which.
        openDay(key, using: repository)
        if !outcome.applied.isEmpty {
            RepbaseCelebrations.show(.mealLogged)
        }
        return outcome
    }

    func applyReusableMeal(
        _ savedMeal: SavedFoodMeal,
        to dates: [Date],
        mealNumber: Int
    ) {
        guard let repository,
              let serverID = savedMeal.serverID,
              mealNumber > 0,
              !dates.isEmpty
        else { return }

        let keys = dates.map(dateKey(for:))
        var snapshots: [String: (date: Date, total: NutritionAmount, mealCount: Int)] = [:]
        for (date, key) in zip(dates, keys) {
            snapshots[key] = (
                Calendar.current.startOfDay(for: date),
                total(on: date),
                loggedMealCount(on: date)
            )
        }
        let generation = connectionGeneration
        isSaving = true
        Task {
            defer { if connectionGeneration == generation { isSaving = false } }
            do {
                _ = try await repository.applyRecipe(
                    serverID,
                    toDates: keys,
                    mealNumber: mealNumber
                )
                // The reply names only the meals written into, and applying to
                // a day that had none also builds the ones before it. Each day
                // is re-read whole so the screens learn about those too.
                for key in keys {
                    let meals = try await repository.openDay(key)
                    guard connectionGeneration == generation else { return }
                    days[key] = meals
                    if let before = snapshots[key],
                       meals.indices.contains(mealNumber - 1) {
                        let appliedMeal = meals[mealNumber - 1]
                        latestMealLogEvent = MealLogEvent(
                            id: UUID(),
                            date: before.date,
                            mealID: appliedMeal.id,
                            before: before.total,
                            after: meals.reduce(.zero) { $0 + $1.totalNutrition },
                            beforeMealCount: before.mealCount,
                            afterMealCount: meals.filter { !$0.entries.isEmpty }.count,
                            shouldCelebrate: true
                        )
                    }
                }
                refreshRecentFoods()
            } catch {
                report(error, generation: generation)
            }
        }
    }

    // MARK: - Goals

    func updateGoals(_ goals: NutritionGoals) {
        guard let repository else { return }
        let generation = connectionGeneration
        isSaving = true
        Task {
            defer { if connectionGeneration == generation { isSaving = false } }
            do {
                let saved = try await repository.saveGoals(goals)
                guard connectionGeneration == generation else { return }
                self.goals = saved
            } catch {
                report(error, generation: generation)
            }
        }
    }

    // MARK: - Keys

    func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    // MARK: - Plumbing

    /// Sends one change, then folds the server's answer into the day it belongs
    /// to. The screens never show a number the server has not confirmed, which
    /// is what keeps a failed write from leaving a total nobody can explain.
    private func perform<Result>(
        on date: Date,
        _ send: @escaping (FoodAPIRepository) async throws -> Result,
        merge: @escaping (inout [FoodMeal], Result) -> Void,
        onSuccess: (() -> Void)? = nil
    ) {
        guard let repository else { return }
        let key = dateKey(for: date)
        let generation = connectionGeneration
        isSaving = true
        Task {
            defer { if connectionGeneration == generation { isSaving = false } }
            do {
                let result = try await send(repository)
                guard connectionGeneration == generation else { return }
                var meals = days[key] ?? []
                merge(&meals, result)
                days[key] = meals
                onSuccess?()
            } catch {
                report(error, generation: generation)
            }
        }
    }

    private func mealServerID(_ id: FoodMeal.ID, on date: Date) -> Int? {
        days[dateKey(for: date)]?.first(where: { $0.id == id })?.serverID
    }

    private static func replace(_ meal: FoodMeal, in meals: inout [FoodMeal]) {
        guard let index = meals.firstIndex(where: { $0.serverID == meal.serverID })
        else { return }
        meals[index] = meal
    }

    /// Re-read the saved meals, without the four other requests connect makes.
    ///
    /// Saving somebody else's meal from a post adds a row this store holds
    /// but did not write, so there has to be something to call that is not
    /// the whole first-load.
    func reloadSavedMeals() async {
        guard let repository else { return }
        let generation = connectionGeneration
        do {
            let loaded = try await repository.savedMeals()
            guard connectionGeneration == generation else { return }
            savedMeals = loaded
        } catch {
            // Left quiet on purpose. This runs behind a save that already
            // succeeded and said so; failing to refresh a list is not worth
            // replacing that confirmation with an error.
        }
    }

    private func refreshRecentFoods() {

        guard let repository else { return }
        let generation = connectionGeneration
        Task {
            let recent = try? await repository.recentFoods()
            guard connectionGeneration == generation, let recent else { return }
            recentFoods = recent
        }
    }

    private func report(_ error: Error, generation: UUID) {
        guard connectionGeneration == generation else { return }
        errorMessage = error.userFacingMessage
    }
}

extension FoodTrackingStore {
    /// Sample data for previews. Nothing here has a server id, because none of
    /// it came from one.
    static var preview: FoodTrackingStore {
        let store = FoodTrackingStore()
        let today = Date()

        // Individual ingredients rather than combined dishes, so the breakdown
        // demonstrates foods being categorized by what they actually are.
        let breakfast = FoodMeal(name: "Meal 1", entries: [
            FoodEntry(
                name: "Greek yogurt",
                nutritionPerServing: NutritionAmount(
                    calories: 120, proteinGrams: 20, carbohydrateGrams: 9, fatGrams: 0
                )
            ),
            FoodEntry(
                name: "Blueberries",
                nutritionPerServing: NutritionAmount(
                    calories: 85, proteinGrams: 1, carbohydrateGrams: 21, fatGrams: 0
                )
            )
        ])
        let lunch = FoodMeal(name: "Meal 2", entries: [
            FoodEntry(
                name: "Grilled chicken breast",
                nutritionPerServing: NutritionAmount(
                    calories: 280, proteinGrams: 52, carbohydrateGrams: 0, fatGrams: 6
                )
            ),
            FoodEntry(
                name: "White rice",
                nutritionPerServing: NutritionAmount(
                    calories: 330, proteinGrams: 6, carbohydrateGrams: 72, fatGrams: 4
                )
            )
        ])
        let snack = FoodMeal(name: "Meal 3", entries: [
            FoodEntry(
                name: "Almonds",
                nutritionPerServing: NutritionAmount(
                    calories: 160, proteinGrams: 6, carbohydrateGrams: 6, fatGrams: 14
                )
            )
        ])

        store.days[store.dateKey(for: today)] = [
            breakfast, lunch, snack, FoodMeal(name: "Meal 4")
        ]
        store.savedMeals = [
            SavedFoodMeal(
                name: "Chicken rice bowl",
                ingredients: [
                    FoodEntry(
                        name: "Chicken breast",
                        nutritionPerServing: NutritionAmount(
                            calories: 280, proteinGrams: 52,
                            carbohydrateGrams: 0, fatGrams: 6
                        )
                    ),
                    FoodEntry(
                        name: "Rice and vegetables",
                        nutritionPerServing: NutritionAmount(
                            calories: 330, proteinGrams: 6,
                            carbohydrateGrams: 72, fatGrams: 4
                        )
                    )
                ]
            )
        ]
        store.recentFoods = breakfast.entries + lunch.entries + snack.entries
        return store
    }
    /// Foods from the public catalogue, through Repbase.
    ///
    /// Returns nothing at all when there is no connection yet rather than
    /// throwing: the picker is reachable before the first sync finishes, and
    /// an empty catalogue with the recents still listed is a better answer
    /// there than an error about a repository.
    func searchCatalogue(_ query: String) async throws -> [FoodDatabaseResult] {
        guard let catalogue else { return [] }
        return try await catalogue.search(query)
    }
}
