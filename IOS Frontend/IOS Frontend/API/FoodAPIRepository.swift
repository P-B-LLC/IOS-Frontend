//
//  FoodAPIRepository.swift
//  IOS Frontend
//
//  OAS-generated food, meal, recipe and nutrition-goal operations.
//

import Foundation
import RepbaseAPI

/// Converts between the decimals the food screens hold and the strings the
/// contract carries them in.
///
/// The API sends every nutrition figure as a string, because a calorie count
/// that travels as a JSON number comes back from some parsers as 233.99999.
/// Both directions live here so a number cannot be rounded one way on the way
/// out and another way on the way back.
nonisolated enum FoodDecimal {
    static func string(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value)
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 2,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            ))
            .stringValue
    }

    /// Zero when the value is absent or unreadable.
    ///
    /// A missing figure means nothing was entered for it, and nothing entered
    /// is nought grams; there is no separate "unknown" for a card to draw.
    static func value(_ text: String?) -> Decimal {
        guard let text, let value = Decimal(string: text) else { return 0 }
        return value
    }
}

actor FoodAPIRepository {
    private let configuration: APIConfiguration
    private let client: Client

    init(configuration: APIConfiguration, token: String) throws {
        self.configuration = configuration
        client = try RepbaseAPIClientFactory.makeAuthenticated(
            serverURL: configuration.serverURL,
            token: token,
            allowInsecureLocalhost: configuration.allowsInsecureLocalhost
        )
    }

    // MARK: - Reading

    /// Every meal between two dates, grouped by the day it belongs to.
    ///
    /// Grouped here rather than in the store because the server already orders
    /// meals by date and position, and rebuilding that order on the device from
    /// a flat list is how the two come to disagree about which meal is second.
    func days(from start: String, to end: String) async throws -> [String: [FoodMeal]] {
        var page: Int?
        var visited: Set<Int> = []
        var days: [String: [FoodMeal]] = [:]
        repeat {
            let output = try await client.foodMealsList(
                query: .init(end: end, page: page, start: start)
            )
            let response: Components.Schemas.PaginatedFoodMealList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            for payload in response.results {
                days[payload.date, default: []].append(Self.meal(from: payload))
            }
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return days
    }

    /// A day's meals, with the empty slots a day starts with.
    ///
    /// The slots come from the server, not from the app drawing four of them:
    /// a slot the app invented is one the server has never heard of, and
    /// logging into it would have nowhere to go.
    func openDay(_ date: String) async throws -> [FoodMeal] {
        let output = try await client.foodMealsEnsureDayCreate(
            body: .json(Components.Schemas.EnsureFoodDayRequest(date: date))
        )
        switch output {
        case .ok(let response):
            return try response.body.json.map(Self.meal(from:))
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Copies a whole day's eating onto another day, and answers with the
    /// day it landed on.
    ///
    /// One call rather than replaying every meal and every food from here: the
    /// server writes it in a single transaction, so a connection that drops
    /// halfway cannot leave a day holding half of yesterday. It also answers
    /// with the target day in full, which is why nothing has to be re-read
    /// afterwards.
    ///
    /// A refusal (nothing to copy, or a day that already has food) comes back
    /// as a 400 the contract does not describe, so the body is decoded for the
    /// sentence the server put in it rather than reported as a status code.
    func copyDay(from source: String, to target: String) async throws -> [FoodMeal] {
        let output = try await client.foodMealsCopyDayCreate(
            body: .json(
                Components.Schemas.CopyFoodDayRequest(
                    sourceDate: source,
                    targetDate: target
                )
            )
        )
        switch output {
        case .ok(let response):
            return try response.body.json.map(Self.meal(from:))
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(
                statusCode: statusCode,
                payload: payload
            )
        }
    }

    /// Foods logged before, most recent first, one row per name.
    func recentFoods() async throws -> [FoodEntry] {
        let output = try await client.foodMealsRecentFoodsList()
        switch output {
        case .ok(let response):
            return try response.body.json.map { payload in
                FoodEntry(
                    name: payload.name,
                    servings: FoodDecimal.value(payload.servings),
                    nutritionPerServing: NutritionAmount(
                        calories: FoodDecimal.value(payload.calories),
                        proteinGrams: FoodDecimal.value(payload.proteinGrams),
                        carbohydrateGrams: FoodDecimal.value(payload.carbohydrateGrams),
                        fatGrams: FoodDecimal.value(payload.fatGrams)
                    )
                )
            }
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func savedMeals() async throws -> [SavedFoodMeal] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [SavedFoodMeal] = []
        repeat {
            let output = try await client.foodSavedMealsList(query: .init(page: page))
            let response: Components.Schemas.PaginatedSavedFoodMealList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results.map(Self.savedMeal(from:)))
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    func goals() async throws -> NutritionGoals {
        let output = try await client.foodGoalsRetrieve()
        switch output {
        case .ok(let response):
            return Self.goals(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Meals

    func addMeal(named name: String, on date: String) async throws -> FoodMeal {
        let output = try await client.foodMealsCreate(
            body: .json(
                // Position is left to the server, which numbers a new meal
                // after whatever is already on that day.
                Components.Schemas.FoodMealRequest(date: date, name: name)
            )
        )
        switch output {
        case .created(let response):
            return Self.meal(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func renameMeal(_ serverID: Int, to name: String) async throws -> FoodMeal {
        let output = try await client.foodMealsPartialUpdate(
            path: .init(id: serverID),
            body: .json(Components.Schemas.PatchedFoodMealRequest(name: name))
        )
        switch output {
        case .ok(let response):
            return Self.meal(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func deleteMeal(_ serverID: Int) async throws {
        let output = try await client.foodMealsDestroy(path: .init(id: serverID))
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Foods

    /// Adds a food to a meal, or rewrites one already in it.
    ///
    /// Which of the two it is comes from the entry carrying a server id, not
    /// from a flag the caller sets: an entry that has one exists on the server
    /// and an entry that has none does not.
    @discardableResult
    func saveFood(_ entry: FoodEntry, inMeal mealID: Int) async throws -> FoodEntry {
        if let serverID = entry.serverID {
            let output = try await client.foodEntriesPartialUpdate(
                path: .init(id: serverID),
                body: .json(
                    Components.Schemas.PatchedFoodEntryRequest(
                        name: entry.name,
                        servings: FoodDecimal.string(entry.servings),
                        calories: FoodDecimal.string(entry.nutritionPerServing.calories),
                        proteinGrams: FoodDecimal.string(entry.nutritionPerServing.proteinGrams),
                        carbohydrateGrams: FoodDecimal.string(
                            entry.nutritionPerServing.carbohydrateGrams
                        ),
                        fatGrams: FoodDecimal.string(entry.nutritionPerServing.fatGrams)
                    )
                )
            )
            switch output {
            case .ok(let response):
                return Self.entry(from: try response.body.json)
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
        }

        let output = try await client.foodEntriesCreate(
            body: .json(
                Components.Schemas.FoodEntryRequest(
                    meal: mealID,
                    name: entry.name,
                    servings: FoodDecimal.string(entry.servings),
                    calories: FoodDecimal.string(entry.nutritionPerServing.calories),
                    proteinGrams: FoodDecimal.string(entry.nutritionPerServing.proteinGrams),
                    carbohydrateGrams: FoodDecimal.string(
                        entry.nutritionPerServing.carbohydrateGrams
                    ),
                    fatGrams: FoodDecimal.string(entry.nutritionPerServing.fatGrams)
                )
            )
        )
        switch output {
        case .created(let response):
            return Self.entry(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func deleteFood(_ serverID: Int) async throws {
        let output = try await client.foodEntriesDestroy(path: .init(id: serverID))
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Recipes

    @discardableResult
    func saveRecipe(_ recipe: SavedFoodMeal) async throws -> SavedFoodMeal {
        let ingredients = recipe.ingredients.map { ingredient in
            Components.Schemas.SavedFoodIngredientRequest(
                name: ingredient.name,
                servings: FoodDecimal.string(ingredient.servings),
                calories: FoodDecimal.string(ingredient.nutritionPerServing.calories),
                proteinGrams: FoodDecimal.string(ingredient.nutritionPerServing.proteinGrams),
                carbohydrateGrams: FoodDecimal.string(
                    ingredient.nutritionPerServing.carbohydrateGrams
                ),
                fatGrams: FoodDecimal.string(ingredient.nutritionPerServing.fatGrams)
            )
        }

        if let serverID = recipe.serverID {
            let output = try await client.foodSavedMealsUpdate(
                path: .init(id: serverID),
                body: .json(
                    Components.Schemas.SavedFoodMealRequest(
                        name: recipe.name,
                        ingredients: ingredients,
                        cookingInstructions: recipe.cookingInstructions
                    )
                )
            )
            switch output {
            case .ok(let response):
                return Self.savedMeal(from: try response.body.json)
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
        }

        let output = try await client.foodSavedMealsCreate(
            body: .json(
                Components.Schemas.SavedFoodMealRequest(
                    name: recipe.name,
                    ingredients: ingredients,
                    cookingInstructions: recipe.cookingInstructions
                )
            )
        )
        switch output {
        case .created(let response):
            return Self.savedMeal(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func deleteRecipe(_ serverID: Int) async throws {
        let output = try await client.foodSavedMealsDestroy(path: .init(id: serverID))
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Copies a recipe into the same numbered meal on each of several days.
    ///
    /// One call rather than one per day: the server does the whole set inside a
    /// transaction, so a week of meal prep either lands or does not, and the
    /// app never has to work out which half of it went through.
    func applyRecipe(
        _ serverID: Int,
        toDates dates: [String],
        mealNumber: Int
    ) async throws -> [FoodMeal] {
        let output = try await client.foodSavedMealsApplyCreate(
            path: .init(id: serverID),
            body: .json(
                Components.Schemas.ApplySavedMealRequest(
                    dates: dates,
                    position: mealNumber
                )
            )
        )
        switch output {
        case .ok(let response):
            return try response.body.json.map(Self.meal(from:))
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Goals

    @discardableResult
    func saveGoals(_ goals: NutritionGoals) async throws -> NutritionGoals {
        let output = try await client.foodGoalsPartialUpdate(
            body: .json(
                Components.Schemas.PatchedNutritionGoalRequest(
                    calories: FoodDecimal.string(goals.calories),
                    proteinGrams: FoodDecimal.string(goals.proteinGrams),
                    carbohydrateGrams: FoodDecimal.string(goals.carbohydrateGrams),
                    fatGrams: FoodDecimal.string(goals.fatGrams)
                )
            )
        )
        switch output {
        case .ok(let response):
            return Self.goals(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Mapping

    private static func meal(from payload: Components.Schemas.FoodMeal) -> FoodMeal {
        FoodMeal(
            // Keyed off the server row, so reading the day again hands back
            // the same meal rather than a new one wearing its name.
            id: .stable(forServerID: payload.id),
            serverID: payload.id,
            name: payload.name,
            entries: payload.entries.map(Self.entry(from:))
        )
    }

    private static func entry(from payload: Components.Schemas.FoodEntry) -> FoodEntry {
        FoodEntry(
            // Held by the food editor as a sheet item: a new id mid-edit
            // closes the sheet out from under whoever is typing in it.
            id: .stable(forServerID: payload.id),
            serverID: payload.id,
            name: payload.name,
            servings: FoodDecimal.value(payload.servings),
            nutritionPerServing: NutritionAmount(
                calories: FoodDecimal.value(payload.calories),
                proteinGrams: FoodDecimal.value(payload.proteinGrams),
                carbohydrateGrams: FoodDecimal.value(payload.carbohydrateGrams),
                fatGrams: FoodDecimal.value(payload.fatGrams)
            )
        )
    }

    private static func savedMeal(
        from payload: Components.Schemas.SavedFoodMeal
    ) -> SavedFoodMeal {
        SavedFoodMeal(
            // Same reason as FoodMeal: re-reading the library must not
            // rename what is in it, or the tick on a row just applied lands
            // on an id nothing recognises any more.
            id: .stable(forServerID: payload.id),
            serverID: payload.id,
            name: payload.name,
            ingredients: payload.ingredients.map { ingredient in
                FoodEntry(
                    // The saved-meal ingredient row, so editing a recipe
                    // does not renumber the lines under the cursor.
                    id: .stable(forServerID: ingredient.id),
                    serverID: ingredient.id,
                    name: ingredient.name,
                    servings: FoodDecimal.value(ingredient.servings),
                    nutritionPerServing: NutritionAmount(
                        calories: FoodDecimal.value(ingredient.calories),
                        proteinGrams: FoodDecimal.value(ingredient.proteinGrams),
                        carbohydrateGrams: FoodDecimal.value(ingredient.carbohydrateGrams),
                        fatGrams: FoodDecimal.value(ingredient.fatGrams)
                    )
                )
            },
            cookingInstructions: payload.cookingInstructions ?? ""
        )
    }

    private static func goals(
        from payload: Components.Schemas.NutritionGoal
    ) -> NutritionGoals {
        NutritionGoals(
            calories: FoodDecimal.value(payload.calories),
            proteinGrams: FoodDecimal.value(payload.proteinGrams),
            carbohydrateGrams: FoodDecimal.value(payload.carbohydrateGrams),
            fatGrams: FoodDecimal.value(payload.fatGrams)
        )
    }

    // MARK: - Paging

    private func nextPage(
        _ next: String?,
        visited: inout Set<Int>
    ) throws -> Int? {
        guard let next else { return nil }
        guard let url = URL(string: next, relativeTo: configuration.serverURL)?.absoluteURL,
              Self.sameOrigin(url, configuration.serverURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let pageValue = components.queryItems?
                .first(where: { $0.name == "page" })?.value,
              let page = Int(pageValue),
              page > 0,
              visited.insert(page).inserted else {
            throw APIServiceError.untrustedPaginationURL
        }
        return page
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "https" ? 443 : 80
    }
}

// MARK: - Public food catalogue

/// Food search, through Repbase rather than at a catalogue directly.
///
/// This used to call Open Food Facts from the device on every keystroke. Three
/// things were wrong with that and only one of them was about food data.
///
/// It made the privacy policy untrue: every search sent what somebody was
/// eating, and the address they were eating it at, to a third party, while the
/// policy in Settings said no third party received anything.
///
/// It was the usage Open Food Facts asks people not to make -- their limit is
/// ten searches a minute per address and their documentation says in as many
/// words not to wire it to a search-as-you-type field, which is exactly where
/// it was wired.
///
/// And it read a catalogue's numbers on the phone, where a misread is a wrong
/// calorie count in somebody's log and nobody can see it happen. The server
/// reads USDA FoodData Central now, in one place, under test.
///
/// What stays true is the part worth keeping: whatever is chosen here is
/// copied into a Repbase food entry, so a logged meal never depends on a
/// catalogue afterwards.
actor FoodDatabaseRepository {
    private let client: Client

    init(configuration: APIConfiguration, token: String) throws {
        client = try RepbaseAPIClientFactory.makeAuthenticated(
            serverURL: configuration.serverURL,
            token: token,
            allowInsecureLocalhost: configuration.allowsInsecureLocalhost
        )
    }

    func search(_ query: String) async throws -> [FoodDatabaseResult] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return [] }

        let output = try await client.foodSearchList(query: .init(q: term))
        switch output {
        case .ok(let response):
            return try response.body.json.map { payload in
                FoodDatabaseResult(
                    sourceID: payload.sourceId,
                    servingDescription: payload.servingDescription,
                    entry: FoodEntry(
                        name: Self.title(payload.name, brand: payload.brand),
                        servings: 1,
                        nutritionPerServing: NutritionAmount(
                            calories: FoodDecimal.value(payload.calories),
                            proteinGrams: FoodDecimal.value(payload.proteinGrams),
                            carbohydrateGrams: FoodDecimal.value(
                                payload.carbohydrateGrams
                            ),
                            fatGrams: FoodDecimal.value(payload.fatGrams)
                        )
                    )
                )
            }
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(
                statusCode: statusCode,
                payload: payload
            )
        }
    }

    private static func title(_ name: String, brand: String) -> String {
        let brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brand.isEmpty,
              !name.localizedCaseInsensitiveContains(brand) else { return name }
        return "\(name) · \(brand)"
    }
}

/// A catalogue row: the food, and what the figures are measured against.
///
/// The serving is carried beside the entry rather than pushed into its name.
/// It is the one thing a person has to read before agreeing to the numbers --
/// nearly everything here is per 100 g -- and a name is not where that belongs.
nonisolated struct FoodDatabaseResult: Identifiable, Hashable, Sendable {
    let sourceID: String
    let servingDescription: String
    let entry: FoodEntry

    var id: String { sourceID }
}
