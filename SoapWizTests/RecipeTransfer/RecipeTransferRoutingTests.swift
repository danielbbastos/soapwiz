import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Which of the two paths a given input takes, and what the plan says will
/// happen before anything is written.
@MainActor
@Suite
struct RecipeTransferRoutingTests {

    private let fixture: RecipeTransferFixture

    init() throws {
        fixture = try RecipeTransferFixture()
    }

    private func payload(_ recipes: [Recipe]) -> RecipeTransferData {
        fixture.context.processPendingChanges()
        return RecipeTransferEncoder.payload(for: recipes)
    }

    // MARK: - Routing

    /// The exact path runs without the model even being asked, which is what
    /// makes import work on a device Apple Intelligence can't run on.
    @Test func extract_TextCarryingAPayload_NeverCallsTheExtractor() async throws {
        let extractor = StubRecipeExtractor(error: .modelUnavailable("should not be reached"))
        let model = RecipeImportViewModel(extractor: extractor)
        model.rawText = RecipeTextExporter.clipboardText(for: fixture.populatedRecipe())

        await model.extract(inventory: [], collections: [])

        #expect(model.phase == .exactReview)
        #expect(extractor.recorder.lastText == nil)
        #expect(model.transferPlan != nil)
    }

    @Test func extract_TextWithNoMarker_StillTakesTheLanguageModelPath() async throws {
        var draft = RecipeImportDraft()
        draft.name = "Read By The Model"
        draft.oils = [ImportedIngredient(name: "Olive Oil", amount: 100, unit: nil)]
        let extractor = StubRecipeExtractor(draft: draft)
        let model = RecipeImportViewModel(extractor: extractor)
        model.rawText = "Olive Oil 100%\nSuperfat 5%"

        await model.extract(inventory: fixture.inventoryForImport(), collections: [])

        #expect(model.phase == .review)
        #expect(model.transferPlan == nil)
        #expect(extractor.recorder.lastText != nil)
    }

    /// A recipe mangled in transit should still import approximately: the
    /// readable text above the marker is intact.
    @Test func extract_TruncatedPayload_FallsBackToTheLanguageModel() async throws {
        var draft = RecipeImportDraft()
        draft.oils = [ImportedIngredient(name: "Olive Oil", amount: 100, unit: nil)]
        let extractor = StubRecipeExtractor(draft: draft)
        let model = RecipeImportViewModel(extractor: extractor)
        let clipboard = RecipeTextExporter.clipboardText(for: fixture.populatedRecipe())
        model.rawText = String(clipboard.prefix(clipboard.count - 200))

        await model.extract(inventory: fixture.inventoryForImport(), collections: [])

        #expect(model.phase == .review)
        #expect(extractor.recorder.lastText != nil)
    }

    /// The one case that interrupts rather than falling back: the user has a
    /// real recipe in hand and an app update is what stands between them.
    @Test func extract_PayloadFromANewerVersion_FailsRatherThanGuessing() async throws {
        let extractor = StubRecipeExtractor(error: .modelUnavailable("should not be reached"))
        let model = RecipeImportViewModel(extractor: extractor)
        var newer = payload([fixture.populatedRecipe()])
        newer.version = RecipeTransferData.currentVersion + 1
        model.rawText = try #require(RecipeTransferMarker.line(for: newer))

        await model.extract(inventory: [], collections: [])

        guard case .failed(let error) = model.phase else {
            Issue.record("Expected a failure, got \(model.phase)")
            return
        }
        #expect(error.errorDescription?.contains("newer version") == true)
        #expect(extractor.recorder.lastText == nil)
    }

    @Test func extract_PayloadWithNoRecipes_ReportsNothingToImport() async throws {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: RecipeImportDraft()))
        let empty = RecipeTransferData(exportedAt: .now, ingredients: [], recipes: [])
        model.rawText = try #require(RecipeTransferMarker.line(for: empty))

        await model.extract(inventory: [], collections: [])

        #expect(model.phase == .failed(.nothingRecognised))
    }

    @Test func textCarriesExactPayload_MarkerPresent_IsTrue() {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: RecipeImportDraft()))

        model.rawText = "Olive Oil 100%"
        #expect(!model.textCarriesExactPayload)

        model.rawText = RecipeTextExporter.clipboardText(for: fixture.populatedRecipe())
        #expect(model.textCarriesExactPayload)
    }

    @Test func returnToInput_AfterReadingAPayload_ForgetsIt() async throws {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: RecipeImportDraft()))
        model.rawText = RecipeTextExporter.clipboardText(for: fixture.populatedRecipe())
        await model.extract(inventory: [], collections: [])

        model.returnToInput()

        #expect(model.phase == .input)
        #expect(model.transferPlan == nil)
    }

    // MARK: - Plan

    @Test func plan_EmptyInventory_SaysEveryIngredientWillBeCreated() {
        let plan = RecipeTransferPlan(
            payload: payload([fixture.populatedRecipe()]),
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

        let plan = RecipeTransferPlan(payload: payload([recipe]), inventory: inventory, collections: [])

        #expect(plan.ingredientsToCreate.isEmpty)
        #expect(plan.matchedIngredients.count == 1)
    }

    @Test func plan_MatchedIngredientWithSameChemistry_ReportsNoConflict() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", sap: 0.1345), percentage: 100, to: recipe)
        let inventory = try fixture.context.fetch(FetchDescriptor<Ingredient>())

        let plan = RecipeTransferPlan(payload: payload([recipe]), inventory: inventory, collections: [])

        #expect(plan.conflictingIngredients.isEmpty)
    }

    /// The recipient's values win, so a difference has to be visible: the
    /// recipe will not calculate the way it did for the sender.
    @Test func plan_MatchedIngredientWithDifferentSAP_ReportsAConflict() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", sap: 0.1345), percentage: 100, to: recipe)
        var built = payload([recipe])
        built.ingredients[0].sapValue = 0.9999
        let inventory = try fixture.context.fetch(FetchDescriptor<Ingredient>())

        let plan = RecipeTransferPlan(payload: built, inventory: inventory, collections: [])

        #expect(plan.conflictingIngredients.map(\.name) == ["Olive Oil"])
    }

    @Test func plan_MatchedIngredientWithDifferentProfile_ReportsAConflict() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", profile: .mock), percentage: 100, to: recipe)
        var built = payload([recipe])
        built.ingredients[0].fattyAcidProfile = nil
        let inventory = try fixture.context.fetch(FetchDescriptor<Ingredient>())

        let plan = RecipeTransferPlan(payload: built, inventory: inventory, collections: [])

        #expect(plan.conflictingIngredients.map(\.name) == ["Olive Oil"])
    }

    @Test func plan_IngredientUsedAsAFragrance_IsFiledUnderFragrances() {
        let plan = RecipeTransferPlan(
            payload: payload([fixture.populatedRecipe()]),
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
            payload: payload([fixture.populatedRecipe()]),
            inventory: [],
            collections: [christmas]
        )

        #expect(plan.matchedCollections.keys.sorted() == ["Christmas"])
        #expect(plan.unmatchedCollectionNames == ["Gifts"])
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

        let plan = RecipeTransferPlan(payload: payload([first, second]), inventory: [], collections: [])

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

        let plan = RecipeTransferPlan(payload: payload([recipe]), inventory: [], collections: [])

        #expect(plan.ingredients.count == 2)
        #expect(Set(plan.ingredients.map(\.id)).count == 2)
    }

    @Test func recipeSummaries_UntitledRecipe_StillHasSomethingToShow() {
        let recipe = fixture.recipe(named: "")
        fixture.addOil(fixture.oil("Olive Oil"), percentage: 100, to: recipe)

        let plan = RecipeTransferPlan(payload: payload([recipe]), inventory: [], collections: [])

        #expect(plan.recipeSummaries.first?.displayName == "Untitled Recipe")
    }

    @Test func recipeSummaries_NonSoapRecipe_SaysSoInItsDetail() {
        let recipe = fixture.recipe(named: "Candle")
        recipe.recipeKind = RecipeKind.general.rawValue
        fixture.addOil(fixture.oil("Beeswax"), percentage: 100, to: recipe)

        let plan = RecipeTransferPlan(payload: payload([recipe]), inventory: [], collections: [])

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

extension RecipeTransferFixture {
    /// The fixture's own ingredients, for a test that needs the language-model
    /// path to have something to reconcile against.
    func inventoryForImport() -> [Ingredient] {
        (try? context.fetch(FetchDescriptor<Ingredient>())) ?? []
    }
}
