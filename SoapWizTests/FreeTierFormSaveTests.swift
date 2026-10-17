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

    @Test func ingredientLimit_NewIngredientWithSlotFree_ReturnsNil() throws {
        try fillCustomIngredients(to: FreeTierLimits.customIngredientCap - 1)
        let model = IngredientFormViewModel()
        model.name = "Moon Oil"

        #expect(model.limitReached(gate: free, in: context) == nil)
    }

    @Test func ingredientLimit_NewIngredientAtCap_ReturnsCustomIngredientLimit() throws {
        try fillCustomIngredients(to: FreeTierLimits.customIngredientCap)
        let model = IngredientFormViewModel()
        model.name = "Moon Oil"

        #expect(model.limitReached(gate: free, in: context) == .customIngredientLimit)
    }

    @Test func ingredientLimit_NewIngredientAtCapAsPro_ReturnsNil() throws {
        try fillCustomIngredients(to: FreeTierLimits.customIngredientCap)
        let model = IngredientFormViewModel()

        #expect(model.limitReached(gate: FreeTierGate(isPro: true), in: context) == nil)
    }

    @Test func ingredientLimit_NewIngredientAtCapInTourSandbox_ReturnsNil() throws {
        try fillCustomIngredients(to: FreeTierLimits.customIngredientCap)
        let sandbox = FreeTierGate(isPro: false, isTourSandbox: true)

        #expect(IngredientFormViewModel().limitReached(gate: sandbox, in: context) == nil)
    }

    @Test func ingredientLimit_RenamingLibraryRowAtCap_ReturnsCustomIngredientLimit() throws {
        try fillCustomIngredients(to: FreeTierLimits.customIngredientCap)
        let model = IngredientFormViewModel(ingredient: try libraryRow())
        model.name = "My Own Name"

        #expect(model.limitReached(gate: free, in: context) == .customIngredientLimit)
    }

    @Test func ingredientLimit_RenamingLibraryRowWithSlotFree_ReturnsNil() throws {
        try fillCustomIngredients(to: FreeTierLimits.customIngredientCap - 1)
        let model = IngredientFormViewModel(ingredient: try libraryRow())
        model.name = "My Own Name"

        #expect(model.limitReached(gate: free, in: context) == nil)
    }

    @Test func ingredientLimit_ChemistryOnlyEditOfLibraryRowAtCap_ReturnsNil() throws {
        try fillCustomIngredients(to: FreeTierLimits.customIngredientCap)
        let model = IngredientFormViewModel(ingredient: try libraryRow())
        model.sapValue = "0.123"

        #expect(model.limitReached(gate: free, in: context) == nil)
    }

    @Test func ingredientLimit_UnchangedNameOfLibraryRowAtCap_ReturnsNil() throws {
        try fillCustomIngredients(to: FreeTierLimits.customIngredientCap)
        let model = IngredientFormViewModel(ingredient: try libraryRow())

        #expect(model.limitReached(gate: free, in: context) == nil)
    }

    @Test func ingredientLimit_RenamingBackToCatalogNameAtCap_ReturnsNil() throws {
        try fillCustomIngredients(to: FreeTierLimits.customIngredientCap)
        let row = try libraryRow()
        row.name = "Farm Name"
        let model = IngredientFormViewModel(ingredient: row)
        model.name = entry.name

        #expect(model.limitReached(gate: free, in: context) == nil)
    }

    @Test func ingredientLimit_EditingCustomIngredientAtCap_ReturnsNil() throws {
        try fillCustomIngredients(to: FreeTierLimits.customIngredientCap)
        let custom = try #require(try context.fetch(FetchDescriptor<Ingredient>()).first)
        let model = IngredientFormViewModel(ingredient: custom)
        model.name = "Renamed"

        #expect(model.limitReached(gate: free, in: context) == nil)
    }

    @Test func ingredientLimit_RenamingLibraryRowAtCapAsPro_ReturnsNil() throws {
        try fillCustomIngredients(to: FreeTierLimits.customIngredientCap)
        let model = IngredientFormViewModel(ingredient: try libraryRow())
        model.name = "My Own Name"

        #expect(model.limitReached(gate: FreeTierGate(isPro: true), in: context) == nil)
    }

    @Test func ingredientLimit_UnknownSlugRowRenamedAtCap_ReturnsNil() throws {
        try fillCustomIngredients(to: FreeTierLimits.customIngredientCap)
        let row = Ingredient(name: "Retired", unit: "g")
        row.librarySlug = "no-such-slug"
        context.insert(row)
        try context.save()
        let model = IngredientFormViewModel(ingredient: row)
        model.name = "Renamed"

        #expect(model.limitReached(gate: free, in: context) == nil)
    }
}
