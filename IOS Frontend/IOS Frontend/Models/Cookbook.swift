import Foundation

nonisolated struct Cookbook: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    var name: String
    var recipeCount: Int
    var capacity: Int
    var isFull: Bool { recipeCount >= capacity }
}

nonisolated struct CookbookPostSummary: Equatable, Hashable, Sendable {
    var name: String
    var recipeCount: Int
}

nonisolated struct PublishedCookbook: Sendable {
    var name: String
    var recipes: [SavedFoodMeal]
}
