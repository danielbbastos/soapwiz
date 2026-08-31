import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// What the plan says will happen before anything is written.
///
/// The review screen and the importer both read it, so whatever is asserted here
/// is what the user is shown *and* what lands in the store.
@MainActor
@Suite
struct RecipeTransferPlanTests {

    private let fixture: RecipeTransferFixture

    init() throws {
        fixture = try RecipeTransferFixture()
    }

    // MARK: - Plan

    @Test func plan_EmptyInventory_SaysEveryIngredientWillBeCreated() {
        let plan = RecipeTransferPlan(
            payload: fixture.payload([fixture.populatedRecipe()]),
            inventory: [],
            collections: []
        )

        #expect(plan.recipeCount == 1)
        #expect(plan.ingredientsToCreate.count == 5)
        #expect(plan.matchedIngredients.isEmpty)
        #expect(plan.conflictingIngredients.isEmpty)
    }

    @Test func plan_MatchingInventory_SaysNothingWillBeCreated() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", sap: 0.1345), percentage: 100, to: recipe)
        let inventory = try fixture.context.fetch(FetchDescriptor<Ingredient>())

        let plan = RecipeTransferPlan(payload: fixture.payload([recipe]), inventory: inventory, collections: [])

        #expect(plan.ingredientsToCreate.isEmpty)
        #expect(plan.matchedIngredients.count == 1)
    }

    @Test func plan_MatchedIngredientWithSameChemistry_ReportsNoConflict() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", sap: 0.1345), percentage: 100, to: recipe)
        let inventory = try fixture.context.fetch(FetchDescriptor<Ingredient>())

        let plan = RecipeTransferPlan(payload: fixture.payload([recipe]), inventory: inventory, collections: [])

        #expect(plan.conflictingIngredients.isEmpty)
    }

    /// The recipient's values win, so a difference has to be visible: the
    /// recipe will not calculate the way it did for the sender.
    @Test func plan_MatchedIngredientWithDifferentSAP_ReportsAConflict() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", sap: 0.1345), percentage: 100, to: recipe)
        var built = fixture.payload([recipe])
        built.ingredients[0].sapValue = 0.9999
        let inventory = try fixture.context.fetch(FetchDescriptor<Ingredient>())

        let plan = RecipeTransferPlan(payload: built, inventory: inventory, collections: [])

        #expect(plan.conflictingIngredients.map(\.name) == ["Olive Oil"])
    }

    @Test func plan_MatchedIngredientWithDifferentProfile_ReportsAConflict() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", profile: .mock), percentage: 100, to: recipe)
        var built = fixture.payload([recipe])
        built.ingredients[0].fattyAcidProfile = nil
        let inventory = try fixture.context.fetch(FetchDescriptor<Ingredient>())

        let plan = RecipeTransferPlan(payload: built, inventory: inventory, collections: [])

        #expect(plan.conflictingIngredients.map(\.name) == ["Olive Oil"])
    }

    @Test func plan_IngredientUsedAsAFragrance_IsFiledUnderFragrances() {
        let plan = RecipeTransferPlan(
            payload: fixture.payload([fixture.populatedRecipe()]),
            inventory: [],
            collections: []
        )

        let lavender = plan.ingredients.first { $0.name == "Lavender Essential Oil" }
        #expect(lavender?.suggestedCategoryName == IngredientCategory.Name.fragrances)

        let olive = plan.ingredients.first { $0.name == "Olive Oil" }
        #expect(olive?.suggestedCategoryName == IngredientCategory.Name.oils)
    }

    @Test func plan_CollectionsTheRecipientHas_AreSeparatedFromTheOnesTheyLack() {
        let christmas = fixture.collection("Christmas")

        let plan = RecipeTransferPlan(
            payload: fixture.payload([fixture.populatedRecipe()]),
            inventory: [],
            collections: [christmas]
        )

        #expect(plan.matchedCollections.keys.sorted() == ["Christmas"])
        #expect(plan.unmatchedCollectionNames == ["Gifts"])
    }

    // MARK: - Names that collide with the library

    @Test func plan_NameNotInTheLibrary_IsKept() {
        let plan = RecipeTransferPlan(
            payload: fixture.payload([fixture.populatedRecipe(named: "Brand New Bar")]),
            inventory: [],
            collections: [],
            recipes: []
        )

        #expect(plan.recipeSummaries.first?.resolvedName == "Brand New Bar")
        #expect(plan.renamedRecipes.isEmpty)
    }

    /// Two identical rows in the list is the outcome worth avoiding: the user
    /// has no way to tell which is theirs and which just arrived.
    @Test func plan_NameAlreadyInTheLibrary_TakesTheCopySuffix() {
        let mine = fixture.recipe(named: "Lavender Bar")
        let incoming = fixture.populatedRecipe(named: "Lavender Bar")

        let plan = RecipeTransferPlan(
            payload: fixture.payload([incoming]),
            inventory: [],
            collections: [],
            recipes: [mine]
        )

        #expect(plan.recipeSummaries.first?.resolvedName == "Lavender Bar (copy)")
        #expect(plan.renamedRecipes.count == 1)
        #expect(plan.recipeSummaries.first?.incomingName == "Lavender Bar")
    }

    @Test func plan_NameCollidingTwice_WalksToTheNextFreeSuffix() {
        let mine = fixture.recipe(named: "Lavender Bar")
        let myCopy = fixture.recipe(named: "Lavender Bar (copy)")

        let plan = RecipeTransferPlan(
            payload: fixture.payload([fixture.populatedRecipe(named: "Lavender Bar")]),
            inventory: [],
            collections: [],
            recipes: [mine, myCopy]
        )

        #expect(plan.recipeSummaries.first?.resolvedName == "Lavender Bar (copy 2)")
    }

    @Test func plan_NameCollidingOnCaseOnly_StillCountsAsTaken() {
        let mine = fixture.recipe(named: "LAVENDER BAR")

        let plan = RecipeTransferPlan(
            payload: fixture.payload([fixture.populatedRecipe(named: "Lavender Bar")]),
            inventory: [],
            collections: [],
            recipes: [mine]
        )

        #expect(plan.recipeSummaries.first?.isRenamed == true)
    }

    /// Names claimed earlier in the same payload count as taken too, or a file
    /// holding two "Bar"s would produce the pair it started with.
    @Test func plan_TwoIncomingRecipesSharingAName_AreBothMadeUnique() {
        let first = fixture.recipe(named: "Bar")
        let second = fixture.recipe(named: "Bar")
        fixture.addOil(fixture.oil("Olive Oil"), percentage: 100, to: first)
        fixture.addOil(fixture.oil("Coconut Oil"), percentage: 100, to: second)

        let plan = RecipeTransferPlan(
            payload: fixture.payload([first, second]),
            inventory: [],
            collections: [],
            recipes: []
        )

        #expect(plan.recipeSummaries.map(\.resolvedName) == ["Bar", "Bar (copy)"])
    }

    /// " (copy)" reads as nothing at all, so an untitled recipe is left alone.
    @Test func plan_UntitledRecipes_AreNotSuffixed() {
        let first = fixture.recipe(named: "")
        let second = fixture.recipe(named: "")
        fixture.addOil(fixture.oil("Olive Oil"), percentage: 100, to: first)
        fixture.addOil(fixture.oil("Coconut Oil"), percentage: 100, to: second)

        let plan = RecipeTransferPlan(
            payload: fixture.payload([first, second]),
            inventory: [],
            collections: [],
            recipes: []
        )

        #expect(plan.recipeSummaries.allSatisfy { $0.resolvedName.isEmpty })
        #expect(plan.recipeSummaries.allSatisfy { $0.displayName == "Untitled Recipe" })
        #expect(plan.renamedRecipes.isEmpty)
    }

    // MARK: - Identity

    /// Nothing stops a file holding two recipes with the same name, and the
    /// review screen's whole job is to say what is about to be added. Names
    /// as identity would collapse the two rows into one.
    @Test func recipeSummaries_TwoRecipesSharingAName_StayDistinct() {
        let first = fixture.recipe(named: "Bar")
        let second = fixture.recipe(named: "Bar")
        fixture.addOil(fixture.oil("Olive Oil"), percentage: 100, to: first)
        fixture.addOil(fixture.oil("Coconut Oil"), percentage: 100, to: second)

        let plan = RecipeTransferPlan(payload: fixture.payload([first, second]), inventory: [], collections: [])

        #expect(plan.recipeSummaries.count == 2)
        #expect(Set(plan.recipeSummaries.map(\.id)).count == 2)
    }

    /// The sending side pools ingredients by model identity, so a CloudKit
    /// duplicate the sender hasn't merged yet arrives as two entries sharing a
    /// name. They must remain two rows.
    @Test func ingredients_TwoEntriesSharingAName_StayDistinct() {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", sap: 0.1345), percentage: 50, to: recipe)
        fixture.addOil(fixture.oil("Olive Oil", sap: 0.1400), percentage: 50, to: recipe)

        let plan = RecipeTransferPlan(payload: fixture.payload([recipe]), inventory: [], collections: [])

        #expect(plan.ingredients.count == 2)
        #expect(Set(plan.ingredients.map(\.id)).count == 2)
    }

    @Test func recipeSummaries_UntitledRecipe_StillHasSomethingToShow() {
        let recipe = fixture.recipe(named: "")
        fixture.addOil(fixture.oil("Olive Oil"), percentage: 100, to: recipe)

        let plan = RecipeTransferPlan(payload: fixture.payload([recipe]), inventory: [], collections: [])

        #expect(plan.recipeSummaries.first?.displayName == "Untitled Recipe")
    }

    @Test func recipeSummaries_NonSoapRecipe_SaysSoInItsDetail() {
        let recipe = fixture.recipe(named: "Candle")
        recipe.recipeKind = RecipeKind.general.rawValue
        fixture.addOil(fixture.oil("Beeswax"), percentage: 100, to: recipe)

        let plan = RecipeTransferPlan(payload: fixture.payload([recipe]), inventory: [], collections: [])

        #expect(plan.recipeSummaries.first?.detail == "Non-soap · 1 ingredient")
    }

    @Test func plan_EmptyPayload_IsEmpty() {
        let plan = RecipeTransferPlan(
            payload: RecipeTransferData(exportedAt: .now, ingredients: [], recipes: []),
            inventory: [],
            collections: []
        )

        #expect(plan.isEmpty)
    }
}
