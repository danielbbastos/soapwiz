import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The decision the forms take on Save: whether the free tier lets it through.
@Suite("Free tier form saves")
@MainActor
struct FreeTierFormSaveTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let entry: IngredientLibraryEntry
    private let free = FreeTierGate(isPro: false)

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
        entry = try #require(IngredientLibrary.bundled.entries.first)
    }

    private func fillRecipes(to count: Int) throws -> [Recipe] {
        let recipes = (0..<count).map { Recipe(name: "Recipe \($0)") }
        recipes.forEach { context.insert($0) }
        try context.save()
        return recipes
    }

    private func fillCustomIngredients(to count: Int) throws {
        for index in 0..<count {
            context.insert(Ingredient(name: "Mine \(index)"))
        }
        try context.save()
    }

    private func libraryRow() throws -> Ingredient {
        let row = Ingredient(name: entry.name, unit: "g")
        row.librarySlug = entry.slug
        context.insert(row)
        try context.save()
        return row
    }

    // MARK: Recipe form

    @Test func recipeLimit_NewRecipeWithSlotFree_ReturnsNil() throws {
        _ = try fillRecipes(to: FreeTierLimits.recipeCap - 1)

        #expect(RecipeFormViewModel().limitReached(gate: free, in: context) == nil)
    }

    @Test func recipeLimit_NewRecipeAtCap_ReturnsRecipeLimit() throws {
        _ = try fillRecipes(to: FreeTierLimits.recipeCap)

        #expect(RecipeFormViewModel().limitReached(gate: free, in: context) == .recipeLimit)
    }

    @Test func recipeLimit_NewRecipeAtCapAsPro_ReturnsNil() throws {
        _ = try fillRecipes(to: FreeTierLimits.recipeCap)

        #expect(RecipeFormViewModel().limitReached(gate: FreeTierGate(isPro: true), in: context) == nil)
    }

    @Test func recipeLimit_NewRecipeAtCapInTourSandbox_ReturnsNil() throws {
        _ = try fillRecipes(to: FreeTierLimits.recipeCap)
        let sandbox = FreeTierGate(isPro: false, isTourSandbox: true)

        #expect(RecipeFormViewModel().limitReached(gate: sandbox, in: context) == nil)
    }

    @Test func recipeLimit_EditingAtCap_ReturnsNil() throws {
        let recipes = try fillRecipes(to: FreeTierLimits.recipeCap)
        let model = RecipeFormViewModel()
        model.load(from: try #require(recipes.first))

        #expect(model.limitReached(gate: free, in: context) == nil)
    }

    @Test func recipeLimit_EditingOverCap_ReturnsNil() throws {
        let recipes = try fillRecipes(to: FreeTierLimits.recipeCap + 4)
        let model = RecipeFormViewModel()
        model.load(from: try #require(recipes.first))

        #expect(model.limitReached(gate: free, in: context) == nil)
    }

    // MARK: Ingredient form

    @Test func save_NewCustomIngredientBeyondThree_InsertsIt() throws {
        try fillCustomIngredients(to: 5)
        let model = IngredientFormViewModel()
        model.name = "Moon Oil"

        let saved = try #require(model.save(context: context))

        #expect(saved.name == "Moon Oil")
        #expect(try context.fetchCount(FetchDescriptor<Ingredient>()) == 6)
    }

    @Test func save_RenamingLibraryRowWithManyCustomIngredients_AppliesTheName() throws {
        try fillCustomIngredients(to: 5)
        let row = try libraryRow()
        let model = IngredientFormViewModel(ingredient: row)
        model.name = "My Own Name"

        model.save(context: context)

        #expect(row.name == "My Own Name")
    }

    @Test func save_ManyCustomIngredientsDoNotAffectTheRecipeCap() throws {
        try fillCustomIngredients(to: 5)
        _ = try fillRecipes(to: FreeTierLimits.recipeCap)

        #expect(RecipeFormViewModel().limitReached(gate: free, in: context) == .recipeLimit)
    }
}
