import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Choosing which recipes of a multi-recipe file to import.
///
/// The selection is transient review state: the plan answers every question
/// about what would happen over the ticked recipes alone, and the importer and
/// the free-tier check read those answers rather than the whole payload.
@MainActor
@Suite
struct RecipeTransferSelectionTests {

    private let fixture: RecipeTransferFixture
    private let destination: RecipeTransferFixture

    init() throws {
        fixture = try RecipeTransferFixture()
        destination = try RecipeTransferFixture()
    }

    /// A one-oil recipe. Oils are shared between recipes by passing the same
    /// `Ingredient`, which the payload then pools once.
    private func recipe(_ name: String, oils: [Ingredient], collections: [RecipeCollection] = []) -> Recipe {
        let recipe = fixture.recipe(named: name)
        for oil in oils {
            fixture.addOil(oil, percentage: 100 / Double(oils.count), to: recipe)
        }
        recipe.collections = collections
        return recipe
    }

    private func plan(
        _ recipes: [Recipe],
        inventory: [Ingredient] = [],
        collections: [RecipeCollection] = [],
        library: [Recipe] = []
    ) -> RecipeTransferPlan {
        RecipeTransferPlan(
            payload: fixture.payload(recipes),
            inventory: inventory,
            collections: collections,
            recipes: library
        )
    }

    // MARK: - Default

    @Test func plan_Default_SelectsEveryRecipe() {
        let plan = plan([
            recipe("A", oils: [fixture.oil("Oil A")]),
            recipe("B", oils: [fixture.oil("Oil B")]),
            recipe("C", oils: [fixture.oil("Oil C")])
        ])

        #expect(plan.selectedRecipeIDs == [0, 1, 2])
        #expect(plan.recipeCount == 3)
        #expect(plan.hasSelection)
        #expect(plan.isMultiRecipe)
        #expect(plan.selectedRecipes.map(\.id) == [0, 1, 2])
    }

    @Test func plan_SingleRecipe_IsNotMultiRecipe() {
        let plan = plan([recipe("A", oils: [fixture.oil("Oil A")])])

        #expect(!plan.isMultiRecipe)
        #expect(plan.recipeCount == 1)
    }

    @Test func selecting_IdsOutsideThePayload_AreIgnored() {
        let plan = plan([
            recipe("A", oils: [fixture.oil("Oil A")]),
            recipe("B", oils: [fixture.oil("Oil B")])
        ]).selecting([1, 7, -1])

        #expect(plan.selectedRecipeIDs == [1])
        #expect(plan.recipeSummaries.count == 2)
        #expect(plan.isSelected(1))
        #expect(!plan.isSelected(0))
    }

    // MARK: - Ingredients

    @Test func selecting_DropsIngredientsOnlyAnUntickedRecipeUses() {
        let plan = plan([
            recipe("A", oils: [fixture.oil("Oil A")]),
            recipe("B", oils: [fixture.oil("Oil B")])
        ]).selecting([1])

        #expect(plan.ingredientsToCreate.map(\.name) == ["Oil B"])
        #expect(plan.ingredients.count == 2)
    }

    @Test func selecting_IngredientSharedWithATickedRecipe_Stays() {
        let shared = fixture.oil("Shared Oil")
        let plan = plan([
            recipe("A", oils: [shared, fixture.oil("Only A")]),
            recipe("B", oils: [shared])
        ]).selecting([1])

        #expect(plan.ingredientsToCreate.map(\.name) == ["Shared Oil"])
    }

    @Test func selecting_ConflictOnlyAnUntickedRecipeHas_Drops() throws {
        let existing = destination.oil("Olive Oil", sap: 0.5)
        let plan = plan([
            recipe("A", oils: [fixture.oil("Olive Oil", sap: 0.1345)]),
            recipe("B", oils: [fixture.oil("Other Oil")])
        ], inventory: [existing])

        #expect(plan.conflictingIngredients.map(\.name) == ["Olive Oil"])
        #expect(plan.selecting([1]).conflictingIngredients.isEmpty)
        #expect(plan.selecting([1]).ingredientsToCreate.map(\.name) == ["Other Oil"])
        #expect(plan.selecting([0]).ingredientsToCreate.isEmpty)
    }

    // MARK: - Collections

    @Test func selecting_CollectionOnlyAnUntickedRecipeNames_DropsOut() {
        let christmas = fixture.collection("Christmas")
        let gifts = fixture.collection("Gifts")
        let plan = plan([
            recipe("A", oils: [fixture.oil("Oil A")], collections: [christmas]),
            recipe("B", oils: [fixture.oil("Oil B")], collections: [gifts])
        ])

        #expect(plan.unmatchedCollectionNames == ["Christmas", "Gifts"])
        #expect(plan.selecting([1]).unmatchedCollectionNames == ["Gifts"])
        #expect(plan.selecting([]).unmatchedCollectionNames.isEmpty)
    }

    // MARK: - Names and identities

    @Test func selecting_FirstOfTwoSameNamedRecipesUnticked_SecondKeepsTheName() throws {
        let plan = plan([
            recipe("Bar", oils: [fixture.oil("Oil A")]),
            recipe("Bar", oils: [fixture.oil("Oil B")])
        ])

        #expect(plan.recipeSummaries.map(\.resolvedName) == ["Bar", "Bar (copy)"])

        let narrowed = plan.selecting([1])

        let second = try #require(narrowed.selectedRecipes.first)
        #expect(second.resolvedName == "Bar")
        #expect(narrowed.selectedRecipes.filter(\.isRenamed).isEmpty)
    }

    @Test func selecting_BothSameNamedRecipesTicked_StillToldApart() {
        let plan = plan([
            recipe("Bar", oils: [fixture.oil("Oil A")]),
            recipe("Bar", oils: [fixture.oil("Oil B")])
        ]).selecting([1]).selecting([0, 1])

        #expect(plan.selectedRecipes.map(\.resolvedName) == ["Bar", "Bar (copy)"])
    }

    @Test func selecting_UUIDClaimedOnlyByAnUntickedRecipe_IsNotClaimed() throws {
        let first = recipe("First", oils: [fixture.oil("Oil A")])
        let second = recipe("Second", oils: [fixture.oil("Oil B")])
        var payload = fixture.payload([first, second])
        let shared = UUID()
        payload.recipes[0].uuid = shared
        payload.recipes[1].uuid = shared
        let plan = RecipeTransferPlan(payload: payload, inventory: [], collections: [])

        #expect(plan.recipeSummaries[0].resolvedUUID == shared)
        #expect(plan.recipeSummaries[1].resolvedUUID != shared)

        let narrowed = plan.selecting([1])

        #expect(try #require(narrowed.selectedRecipes.first).resolvedUUID == shared)
    }

    @Test func selecting_LibraryRecipe_StillClaimsItsNameAndIdentity() throws {
        let mine = recipe("Bar", oils: [fixture.oil("Oil A")])
        let incoming = recipe("Bar", oils: [fixture.oil("Oil B")])
        let plan = plan([incoming], library: [mine]).selecting([0])

        let summary = try #require(plan.selectedRecipes.first)
        #expect(summary.resolvedName == "Bar (copy)")
        #expect(summary.resolvedUUID != mine.uuid)
    }

    /// The review row keeps its notes when unticked, so they have to stay true:
    /// the name is resolved against the library as if the recipe were next.
    @Test func selecting_UntickedRecipeWithALibraryName_StillReportsRenamed() throws {
        let mine = recipe("Bar", oils: [fixture.oil("Oil A")])
        let incoming = recipe("Bar", oils: [fixture.oil("Oil B")])
        let other = recipe("Other", oils: [fixture.oil("Oil C")])
        let plan = plan([incoming, other], library: [mine]).selecting([1])

        let unticked = try #require(plan.recipeSummaries.first)
        #expect(!plan.isSelected(unticked.id))
        #expect(unticked.isRenamed)
        #expect(unticked.resolvedName == "Bar (copy)")
        #expect(plan.selectedRecipes.filter(\.isRenamed).isEmpty)
    }

    @Test func selecting_UntickedRecipeTheLibraryKnows_StillReportsKnown() throws {
        let mine = recipe("Bar", oils: [fixture.oil("Oil A")])
        let other = recipe("Other", oils: [fixture.oil("Oil B")])
        let payload = fixture.payload([mine, other])
        let plan = RecipeTransferPlan(payload: payload, inventory: [], collections: [], recipes: [mine])
            .selecting([1])

        #expect(try #require(plan.recipeSummaries.first).isKnownRecipe)
        #expect(plan.selectedRecipes.filter(\.isKnownRecipe).isEmpty)
    }

    // MARK: - Empty selection

    @Test func selecting_Nothing_HasNoSelectionAndCountsNoRecipes() {
        let plan = plan([
            recipe("A", oils: [fixture.oil("Oil A")]),
            recipe("B", oils: [fixture.oil("Oil B")])
        ]).selecting([])

        #expect(!plan.hasSelection)
        #expect(plan.recipeCount == 0)
        #expect(plan.selectedRecipes.isEmpty)
        #expect(plan.ingredientsToCreate.isEmpty)
        #expect(plan.neededIngredientIDs.isEmpty)
        #expect(!plan.isEmpty)
    }

    // MARK: - Importer

    @Test func apply_EmptySelection_WritesNothing() throws {
        let plan = plan([
            recipe("A", oils: [fixture.oil("Oil A")]),
            recipe("B", oils: [fixture.oil("Oil B")])
        ]).selecting([])

        let imported = RecipeTransferImporter.apply(plan, into: destination.context, categories: [])
        destination.context.processPendingChanges()

        #expect(imported.isEmpty)
        #expect(try destination.context.fetch(FetchDescriptor<Recipe>()).isEmpty)
        #expect(try destination.context.fetch(FetchDescriptor<Ingredient>()).isEmpty)
    }

    @Test func apply_PartialSelection_WritesOnlyTickedRecipesAndTheirIngredients() throws {
        let shared = fixture.oil("Shared Oil")
        let plan = plan([
            recipe("A", oils: [fixture.oil("Only A")]),
            recipe("B", oils: [shared]),
            recipe("C", oils: [shared, fixture.oil("Only C")])
        ]).selecting([1, 2])

        let imported = RecipeTransferImporter.apply(plan, into: destination.context, categories: [])
        destination.context.processPendingChanges()

        #expect(imported.map(\.name) == ["B", "C"])
        let ingredients = try destination.context.fetch(FetchDescriptor<Ingredient>())
        #expect(Set(ingredients.map(\.name)) == ["Shared Oil", "Only C"])
        let recipes = try destination.context.fetch(FetchDescriptor<Recipe>())
        #expect(Set(recipes.map(\.name)) == ["B", "C"])
    }

    @Test func apply_PartialSelection_LinesPointAtTheRightIngredients() throws {
        let shared = fixture.oil("Shared Oil")
        let plan = plan([
            recipe("A", oils: [fixture.oil("Only A")]),
            recipe("B", oils: [shared]),
            recipe("C", oils: [shared, fixture.oil("Only C")])
        ]).selecting([1, 2])

        let imported = RecipeTransferImporter.apply(plan, into: destination.context, categories: [])
        destination.context.processPendingChanges()

        let second = try #require(imported.first { $0.name == "B" })
        let third = try #require(imported.first { $0.name == "C" })
        #expect(second.ingredients.compactMap(\.ingredient?.name) == ["Shared Oil"])
        #expect(Set(third.ingredients.compactMap(\.ingredient?.name)) == ["Shared Oil", "Only C"])
        let sharedOil = try #require(second.ingredients.first?.ingredient)
        #expect(third.ingredients.contains { $0.ingredient === sharedOil })
    }

    @Test func apply_UnticksOneOfTwoSameNamedRecipes_SavesTheSurvivorUnderTheOriginalName() throws {
        let plan = plan([
            recipe("Bar", oils: [fixture.oil("Oil A")]),
            recipe("Bar", oils: [fixture.oil("Oil B")])
        ]).selecting([1])

        let imported = RecipeTransferImporter.apply(plan, into: destination.context, categories: [])

        #expect(imported.map(\.name) == ["Bar"])
    }

    // MARK: - Free tier

    private func tenRecipePlan() -> RecipeTransferPlan {
        plan((0..<10).map { index in
            recipe("Recipe \(index)", oils: [fixture.oil("Custom Oil \(index)")])
        })
    }

    @Test func importFit_TwoOfTenTicked_FitsForAFreeUserWithNoRecipes() {
        let plan = tenRecipePlan().selecting([3, 7])
        let free = FreeTierGate(isPro: false)

        let fit = free.importFit(for: plan, in: destination.context)

        #expect(FreeTierLimits.recipeCap >= 2)
        #expect(fit.incomingRecipes == 2)
        #expect(plan.ingredientsToCreate.count == 2)
        #expect(fit.fits)
    }

    @Test func importFit_OneMoreThanTheCapTicked_ExceedsRecipes() {
        let ticked = Set(0...FreeTierLimits.recipeCap)
        let plan = tenRecipePlan().selecting(ticked)
        let free = FreeTierGate(isPro: false)

        let fit = free.importFit(for: plan, in: destination.context)

        #expect(fit.incomingRecipes == FreeTierLimits.recipeCap + 1)
        #expect(fit.exceedsRecipes)
    }

    @Test func importFit_AllTen_ExceedsRecipes() {
        let free = FreeTierGate(isPro: false)

        #expect(free.importFit(for: tenRecipePlan(), in: destination.context).exceedsRecipes)
    }

    @Test func importFit_IngredientsToCreate_FollowTheSelection() {
        let shared = fixture.oil("Shared Oil")
        let plan = plan([
            recipe("A", oils: [shared, fixture.oil("Only A")]),
            recipe("B", oils: [shared]),
            recipe("C", oils: [fixture.oil("Only C")])
        ])

        #expect(plan.ingredientsToCreate.count == 3)
        #expect(plan.selecting([1]).ingredientsToCreate.count == 1)
        #expect(plan.selecting([0, 1]).ingredientsToCreate.count == 2)
    }

    @Test func importFit_ManyNewIngredientsWithinTheRecipeCap_Fits() {
        let oils = (0..<(FreeTierLimits.recipeCap + 3)).map { fixture.oil("Custom Oil \($0)") }
        let plan = plan([recipe("A", oils: oils)])
        let free = FreeTierGate(isPro: false)

        #expect(plan.ingredientsToCreate.count == oils.count)
        #expect(free.importFit(for: plan, in: destination.context).fits)
    }

}
