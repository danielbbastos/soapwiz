import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Favourites", .serialized)
@MainActor
struct FavoriteTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self,
            Recipe.self, RecipeIngredient.self, RecipeProduct.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    // MARK: - Defaults

    @Test func isFavorite_NewRecipe_DefaultsToFalse() {
        #expect(Recipe(name: "Castile").isFavorite == false)
    }

    @Test func isFavorite_NewIngredient_DefaultsToFalse() {
        #expect(Ingredient(name: "Olive Oil", unit: "g").isFavorite == false)
    }

    @Test func isFavorite_PersistsAcrossFetch() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let recipe = Recipe(name: "Castile")
        recipe.isFavorite = true
        ctx.insert(recipe)
        try ctx.save()

        let fetched = try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first)
        #expect(fetched.isFavorite)
    }

    // MARK: - Ordering

    @Test func favoritesFirst_MixedList_PutsFavoritesFirst() {
        let recipes = [
            Recipe.mock(name: "Aloe"),
            Recipe.mock(name: "Basil", isFavorite: true),
            Recipe.mock(name: "Cedar"),
            Recipe.mock(name: "Dill", isFavorite: true)
        ]

        #expect(recipes.favoritesFirst.map(\.name) == ["Basil", "Dill", "Aloe", "Cedar"])
    }

    /// The guard against reaching for `sorted(by:)`: `sort` is not documented as
    /// stable, so a comparator ranking only `isFavorite` could scramble the
    /// alphabetical order the `@Query` established inside each group.
    @Test func favoritesFirst_PreservesRelativeOrderWithinEachGroup() {
        let recipes = [
            Recipe.mock(name: "Aloe", isFavorite: true),
            Recipe.mock(name: "Basil"),
            Recipe.mock(name: "Cedar", isFavorite: true),
            Recipe.mock(name: "Dill"),
            Recipe.mock(name: "Elder", isFavorite: true),
            Recipe.mock(name: "Fennel")
        ]

        let ordered = recipes.favoritesFirst.map(\.name)
        #expect(ordered == ["Aloe", "Cedar", "Elder", "Basil", "Dill", "Fennel"])
    }

    @Test func favoritesFirst_EmptyList_ReturnsEmpty() {
        #expect([Recipe]().favoritesFirst.isEmpty)
    }

    @Test func favoritesFirst_SingleItem_ReturnsIt() {
        #expect([Recipe.mock(name: "Aloe")].favoritesFirst.map(\.name) == ["Aloe"])
    }

    @Test func favoritesFirst_AllFavorites_PreservesOrder() {
        let recipes = [
            Recipe.mock(name: "Aloe", isFavorite: true),
            Recipe.mock(name: "Basil", isFavorite: true)
        ]

        #expect(recipes.favoritesFirst.map(\.name) == ["Aloe", "Basil"])
    }

    @Test func favoritesFirst_NoFavorites_PreservesOrder() {
        let recipes = [Recipe.mock(name: "Aloe"), Recipe.mock(name: "Basil")]

        #expect(recipes.favoritesFirst.map(\.name) == ["Aloe", "Basil"])
    }

    @Test func favoritesFirst_Ingredients_PutsFavoritesFirst() {
        let ingredients = [
            Ingredient.mock(name: "Coconut Oil"),
            Ingredient.mock(name: "Olive Oil", isFavorite: true)
        ]

        #expect(ingredients.favoritesFirst.map(\.name) == ["Olive Oil", "Coconut Oil"])
    }

    // MARK: - Toggling

    @Test func toggleFavorite_Recipe_FlipsAndPersists() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeListViewModel()

        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)
        try ctx.save()

        model.toggleFavorite(recipe)
        try ctx.save()
        #expect(try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first).isFavorite)

        model.toggleFavorite(recipe)
        try ctx.save()
        #expect(try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first).isFavorite == false)
    }

    @Test func toggleFavorite_Ingredient_FlipsAndPersists() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = IngredientListViewModel()

        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)
        try ctx.save()

        model.toggleFavorite(ingredient)
        try ctx.save()
        #expect(try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first).isFavorite)

        model.toggleFavorite(ingredient)
        try ctx.save()
        #expect(try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first).isFavorite == false)
    }

    // MARK: - Composition with the inventory filter

    /// The inventory list pins *after* filtering, so a favourite that a filter
    /// excludes must stay excluded rather than being pulled back to the top.
    @Test func filterThenFavoritesFirst_ExcludedFavorite_StaysExcluded() {
        let model = IngredientListViewModel()
        model.searchText = "oil"

        let ingredients = [
            Ingredient.mock(name: "Coconut Oil"),
            Ingredient.mock(name: "Lye", isFavorite: true),
            Ingredient.mock(name: "Olive Oil", isFavorite: true)
        ]

        let displayed = model.filtered(ingredients).favoritesFirst
        #expect(displayed.map(\.name) == ["Olive Oil", "Coconut Oil"])
    }
}

extension Recipe {
    static func mock(name: String, isFavorite: Bool = false) -> Recipe {
        let recipe = Recipe(name: name)
        recipe.isFavorite = isFavorite
        return recipe
    }
}

extension Ingredient {
    static func mock(name: String, unit: String = "g", isFavorite: Bool = false) -> Ingredient {
        let ingredient = Ingredient(name: name, unit: unit)
        ingredient.isFavorite = isFavorite
        return ingredient
    }
}
