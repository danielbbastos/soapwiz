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
        #expect(fit.incomingCustomIngredients == 1)
    }

    @Test func importFit_TooManyRecipes_ExceedsRecipes() throws {
        try addRecipes(1)
        let recipes = (0..<3).map { oilRecipe(named: "Bar \($0)", oil: "Moon Oil") }
        let plan = try plan(from: recipes)

        let fit = free.importFit(for: plan, in: destination.context)

        #expect(fit.exceedsRecipes)
        #expect(!fit.exceedsCustomIngredients)
        #expect(fit.existingRecipes == 1)
    }

    @Test func importFit_TooManyCustomIngredients_ExceedsIngredients() throws {
        let plan = try plan(from: [source.populatedRecipe()])

        let fit = free.importFit(for: plan, in: destination.context)

        #expect(fit.exceedsCustomIngredients)
        #expect(!fit.exceedsRecipes)
        #expect(fit.incomingCustomIngredients == 5)
    }

    @Test func importFit_AdoptableLibraryEntryUnderCatalogName_IsNotCounted() throws {
        let entry = try #require(IngredientLibrary.bundled.entries.first)
        let recipe = source.recipe(named: "Library")
        source.addOil(source.oil(entry.name, slug: entry.slug), percentage: 100, to: recipe)
        var payload = source.payload([recipe])
        payload.ingredients[0].librarySlug = entry.slug
        let plan = RecipeTransferPlan(payload: payload, inventory: [], collections: [])

        let fit = free.importFit(for: plan, in: destination.context)

        #expect(plan.ingredientsToCreate.count == 1)
        #expect(fit.incomingCustomIngredients == 0)
    }

    @Test func importFit_MixOfLibraryAndCustom_CountsOnlyCustom() throws {
        let entry = try #require(IngredientLibrary.bundled.entries.first)
        let recipe = source.recipe(named: "Mixed")
        source.addOil(source.oil(entry.name, slug: entry.slug), percentage: 50, to: recipe)
        source.addOil(source.oil("Moon Oil"), percentage: 30, to: recipe)
        source.addOil(source.oil("Star Oil"), percentage: 20, to: recipe)
        var payload = source.payload([recipe])
        payload.ingredients[0].librarySlug = entry.slug
        let plan = RecipeTransferPlan(payload: payload, inventory: [], collections: [])

        let fit = free.importFit(for: plan, in: destination.context)

        #expect(plan.ingredientsToCreate.count == 3)
        #expect(fit.incomingCustomIngredients == 2)
        #expect(fit.fits)
    }

    @Test func importFit_MatchedIngredients_AreNotCounted() throws {
        _ = destination.oil("Moon Oil")
        try destination.context.save()
        let plan = try plan(from: [oilRecipe(named: "One", oil: "Moon Oil")])

        let fit = free.importFit(for: plan, in: destination.context)

        #expect(fit.incomingCustomIngredients == 0)
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

    @Test func matching_CreatedEntry_MovesToMatched() throws {
        let existing = destination.oil("My Olive")
        let plan = try plan(from: [oilRecipe(named: "One", oil: "Moon Oil")])
        let entry = try #require(plan.ingredientsToCreate.first)

        let updated = plan.matching(entry.id, to: existing)

        #expect(updated.ingredientsToCreate.isEmpty)
        #expect(updated.matchedIngredients.map(\.name) == ["Moon Oil"])
        #expect(updated.matchedIngredients.first?.existing === existing)
    }

    @Test func matching_FreesTheCustomSlot() throws {
        let existing = destination.oil("My Olive")
        let plan = try plan(from: [source.populatedRecipe()])
        let entry = try #require(plan.customIngredientsToCreate.first)

        let updated = plan.matching(entry.id, to: existing)

        #expect(updated.customIngredientsToCreate.count == plan.customIngredientsToCreate.count - 1)
    }

    @Test func matching_DifferentChemistry_ReportsAConflict() throws {
        let existing = destination.oil("My Olive", sap: 0.5)
        let plan = try plan(from: [oilRecipe(named: "One", oil: "Moon Oil")])
        let entry = try #require(plan.ingredientsToCreate.first)

        let updated = plan.matching(entry.id, to: existing)

        #expect(updated.conflictingIngredients.map(\.name) == ["Moon Oil"])
    }

    @Test func matching_SameChemistry_ReportsNoConflict() throws {
        let existing = destination.oil("My Olive")
        let plan = try plan(from: [oilRecipe(named: "One", oil: "Moon Oil")])
        let entry = try #require(plan.ingredientsToCreate.first)

        let updated = plan.matching(entry.id, to: existing)

        #expect(updated.conflictingIngredients.isEmpty)
    }

    @Test func matching_LeavesOtherEntriesRecipesAndCollectionsAlone() throws {
        let existing = destination.oil("My Olive")
        let plan = try plan(from: [source.populatedRecipe()])
        let entry = try #require(plan.ingredientsToCreate.first)

        let updated = plan.matching(entry.id, to: existing)

        #expect(updated.ingredients.map(\.id) == plan.ingredients.map(\.id))
        #expect(updated.recipeSummaries.map(\.id) == plan.recipeSummaries.map(\.id))
        #expect(updated.recipeCount == plan.recipeCount)
        #expect(updated.unmatchedCollectionNames == plan.unmatchedCollectionNames)
        #expect(updated.ingredientsToCreate.count == plan.ingredientsToCreate.count - 1)
    }

    @Test func matching_UnknownEntry_ChangesNothing() throws {
        let existing = destination.oil("My Olive")
        let plan = try plan(from: [oilRecipe(named: "One", oil: "Moon Oil")])

        let updated = plan.matching(999, to: existing)

        #expect(updated.ingredientsToCreate.count == plan.ingredientsToCreate.count)
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

    @Test func confirmExactImport_OverTheIngredientCap_InsertsNothing() throws {
        let model = RecipeImportViewModel()
        model.rawText = try destination.pastedFile(source.payload([source.populatedRecipe()]))
        _ = model.adoptPayloadFromText(inventory: [], collections: [], recipes: [])

        let result = model.confirmExactImport(context: destination.context, categories: [], gate: free)

        #expect(result == nil)
        #expect(try destination.context.fetchCount(FetchDescriptor<Recipe>()) == 0)
        #expect(try destination.context.fetchCount(FetchDescriptor<Ingredient>()) == 0)
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

    @Test func useExisting_MatchingEnoughEntries_MakesTheFileFit() throws {
        let entry = try #require(IngredientLibrary.bundled.entries.first)
        let existing = destination.oil(entry.name, slug: entry.slug)
        let model = RecipeImportViewModel()
        model.rawText = try destination.pastedFile(source.payload([source.populatedRecipe()]))
        _ = model.adoptPayloadFromText(inventory: [], collections: [], recipes: [])
        let plan = try #require(model.transferPlan)
        let entries = plan.customIngredientsToCreate
        #expect(entries.count == 5)

        for pick in entries.prefix(2) {
            model.useExisting(pick.id, existing)
        }

        let updated = try #require(model.transferPlan)
        #expect(updated.customIngredientsToCreate.count == 3)
        #expect(free.importFit(for: updated, in: destination.context).fits)
        let result = model.confirmExactImport(context: destination.context, categories: [], gate: free)
        #expect(result?.count == 1)
    }

    @Test func resolveMergedRows_KeepsTheUsersMatch() throws {
        let existing = destination.oil("My Olive")
        try destination.context.save()
        let model = RecipeImportViewModel()
        model.rawText = try destination.pastedFile(source.payload([source.populatedRecipe()]))
        _ = model.adoptPayloadFromText(inventory: [], collections: [], recipes: [])
        let entry = try #require(model.transferPlan?.customIngredientsToCreate.first)
        model.useExisting(entry.id, existing)

        model.resolveMergedRows(in: destination.context)

        let rebuilt = try #require(model.transferPlan)
        let kept = try #require(rebuilt.ingredients.first { $0.id == entry.id })
        #expect(kept.existing === existing)
    }

    @Test func resolveMergedRows_DropsAMatchWhoseIngredientIsGone() throws {
        let existing = destination.oil("My Olive")
        try destination.context.save()
        let model = RecipeImportViewModel()
        model.rawText = try destination.pastedFile(source.payload([source.populatedRecipe()]))
        _ = model.adoptPayloadFromText(inventory: [], collections: [], recipes: [])
        let entry = try #require(model.transferPlan?.customIngredientsToCreate.first)
        model.useExisting(entry.id, existing)
        destination.context.delete(existing)
        try destination.context.save()

        model.resolveMergedRows(in: destination.context)

        let rebuilt = try #require(model.transferPlan)
        let dropped = try #require(rebuilt.ingredients.first { $0.id == entry.id })
        #expect(dropped.willBeCreated)
    }
}
