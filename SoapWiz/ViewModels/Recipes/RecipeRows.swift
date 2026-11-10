import Foundation
import SwiftData

/// Every recipe, by name, kept apart from `@Query`. Watches `Recipe` and
/// `RecipeIngredient`.
typealias RecipeRows = ModelRows<Recipe>

extension ModelRows where Model == Recipe {
    convenience init(
        context: ModelContext,
        importTimeout: Duration = .seconds(120),
        pruneInterval: Duration = .seconds(1),
        fetchRecipes: @escaping @MainActor (ModelContext) throws -> [Recipe] = RecipeRows.fetchAll(in:)
    ) {
        self.init(
            context: context,
            watchedEntities: [Schema.entityName(for: Recipe.self), Schema.entityName(for: RecipeIngredient.self)],
            logCategory: "recipes",
            importTimeout: importTimeout,
            pruneInterval: pruneInterval,
            fetch: fetchRecipes
        )
    }

    var recipes: [Recipe] { rows }

    @discardableResult
    func refreshIfRecipesChanged() -> Bool {
        refreshIfChanged()
    }

    /// Every recipe by name. Injected only so a test can count the fetches or make them fail.
    static func fetchAll(in context: ModelContext) throws -> [Recipe] {
        try context.fetch(FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\Recipe.name)]))
    }
}
