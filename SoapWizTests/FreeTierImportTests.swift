import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Free tier import")
@MainActor
struct FreeTierImportTests {

    private let source: RecipeTransferFixture
    private let destination: RecipeTransferFixture
    private let free = FreeTierGate(isPro: false)

    init() throws {
        source = try RecipeTransferFixture()
        destination = try RecipeTransferFixture()
    }

    private func plan(from recipes: [Recipe]) throws -> RecipeTransferPlan {
        let inventory = try destination.context.fetch(FetchDescriptor<Ingredient>())
        return RecipeTransferPlan(payload: source.payload(recipes), inventory: inventory, collections: [])
    }

    private func addRecipes(_ count: Int) throws {
        for index in 0..<count {
            destination.context.insert(Recipe(name: "Existing \(index)"))
        }
        try destination.context.save()
    }

    /// A recipe whose only ingredient is a made-up oil.
    private func oilRecipe(named name: String, oil: String) -> Recipe {
        let recipe = source.recipe(named: name)
        source.addOil(source.oil(oil), percentage: 100, to: recipe)
        return recipe
    }

    @Test func importFit_SmallFileIntoEmptyStore_Fits() throws {
        let plan = try plan(from: [oilRecipe(named: "One", oil: "Moon Oil")])

        let fit = free.importFit(for: plan, in: destination.context)

        #expect(fit.fits)
        #expect(fit.incomingRecipes == 1)
    }

    @Test func importFit_TooManyRecipes_ExceedsRecipes() throws {
        try addRecipes(1)
        let recipes = (0..<3).map { oilRecipe(named: "Bar \($0)", oil: "Moon Oil") }
        let plan = try plan(from: recipes)

        let fit = free.importFit(for: plan, in: destination.context)

        #expect(fit.exceedsRecipes)
        #expect(fit.existingRecipes == 1)
    }

    @Test func importFit_ManyNewCustomIngredientsWithinRecipeCap_Fits() throws {
        let plan = try plan(from: [source.populatedRecipe()])

        let fit = free.importFit(for: plan, in: destination.context)

        #expect(plan.ingredientsToCreate.count > FreeTierLimits.recipeCap)
        #expect(fit.fits)
        #expect(!fit.exceedsRecipes)
        #expect(fit.explanation == nil)
    }

    @Test func importFit_ManyNewCustomIngredientsIntoStoreWithCustomIngredients_Fits() throws {
        for index in 0..<5 {
            _ = destination.oil("Mine \(index)")
        }
        try destination.context.save()
        let plan = try plan(from: [source.populatedRecipe()])

        #expect(free.importFit(for: plan, in: destination.context).fits)
    }

    @Test func importFit_Pro_FitsAnything() throws {
        let plan = try plan(from: [source.populatedRecipe()])

        #expect(FreeTierGate(isPro: true).importFit(for: plan, in: destination.context).fits)
    }

    @Test func importFit_TourSandbox_FitsAnything() throws {
        let plan = try plan(from: [source.populatedRecipe()])
        let gate = FreeTierGate(isPro: false, isTourSandbox: true)

        #expect(gate.importFit(for: plan, in: destination.context).fits)
    }

    // MARK: Matching

    @Test func plan_ExistingIngredientSameChemistry_ReportsNoConflict() throws {
        _ = destination.oil("Moon Oil")
        try destination.context.save()

        let plan = try plan(from: [oilRecipe(named: "One", oil: "Moon Oil")])

        #expect(plan.ingredientsToCreate.isEmpty)
        #expect(plan.ingredients.compactMap(\.existing).count == 1)
        #expect(plan.conflictingIngredients.isEmpty)
    }

    @Test func plan_ExistingIngredientDifferentChemistry_ReportsAConflict() throws {
        _ = destination.oil("Moon Oil", sap: 0.5)
        try destination.context.save()

        let plan = try plan(from: [oilRecipe(named: "One", oil: "Moon Oil")])

        #expect(plan.conflictingIngredients.map(\.name) == ["Moon Oil"])
    }

    // MARK: Confirming

    @Test func confirmExactImport_OverTheRecipeCap_InsertsNothing() throws {
        let recipes = (0..<4).map { oilRecipe(named: "Bar \($0)", oil: "Moon Oil") }
        let model = RecipeImportViewModel()
        model.rawText = try destination.pastedFile(source.payload(recipes))
        _ = model.adoptPayloadFromText(inventory: [], collections: [], recipes: [])
        #expect(model.phase == .exactReview)

        let result = model.confirmExactImport(context: destination.context, categories: [], gate: free)

        #expect(result == nil)
        #expect(try destination.context.fetchCount(FetchDescriptor<Recipe>()) == 0)
        #expect(try destination.context.fetchCount(FetchDescriptor<Ingredient>()) == 0)
        #expect(model.phase == .exactReview)
    }

    @Test func confirmExactImport_ManyNewCustomIngredientsWithinRecipeCap_ImportsEverything() throws {
        let model = RecipeImportViewModel()
        model.rawText = try destination.pastedFile(source.payload([source.populatedRecipe()]))
        _ = model.adoptPayloadFromText(inventory: [], collections: [], recipes: [])
        let toCreate = try #require(model.transferPlan).ingredientsToCreate.count
        #expect(toCreate > 3)

        let result = model.confirmExactImport(context: destination.context, categories: [], gate: free)

        #expect(result?.count == 1)
        #expect(try destination.context.fetchCount(FetchDescriptor<Recipe>()) == 1)
        #expect(try destination.context.fetchCount(FetchDescriptor<Ingredient>()) >= toCreate)
    }

    @Test func confirmExactImport_Fits_ImportsEverything() throws {
        let recipes = (0..<2).map { oilRecipe(named: "Bar \($0)", oil: "Moon Oil") }
        let model = RecipeImportViewModel()
        model.rawText = try destination.pastedFile(source.payload(recipes))
        _ = model.adoptPayloadFromText(inventory: [], collections: [], recipes: [])

        let result = model.confirmExactImport(context: destination.context, categories: [], gate: free)

        #expect(result?.count == 2)
        #expect(try destination.context.fetchCount(FetchDescriptor<Recipe>()) == 2)
    }

    @Test func confirmExactImport_OverTheCapAsPro_Imports() throws {
        let model = RecipeImportViewModel()
        model.rawText = try destination.pastedFile(source.payload([source.populatedRecipe()]))
        _ = model.adoptPayloadFromText(inventory: [], collections: [], recipes: [])

        let result = model.confirmExactImport(
            context: destination.context,
            categories: [],
            gate: FreeTierGate(isPro: true)
        )

        #expect(result?.count == 1)
    }

}
