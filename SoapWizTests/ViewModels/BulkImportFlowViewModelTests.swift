import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("BulkImportFlowViewModel", .serialized)
@MainActor
struct BulkImportFlowViewModelTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self,
            Provider.self, StorageLocation.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    /// The full schema, not the inventory subset above: `DuplicateMerger` fetches
    /// recipe collections and settings too.
    private func makeFullContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    /// A row as the installer leaves it, carrying the slug the merge pairs on.
    private func installed(
        _ name: String,
        slug: String,
        uuid index: Int,
        in ctx: ModelContext
    ) throws -> Ingredient {
        let row = Ingredient(name: name, unit: IngredientUnit.grams.rawValue)
        row.librarySlug = slug
        row.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)"))
        ctx.insert(row)
        return row
    }

    private func makeIngredients(_ names: [String], in context: ModelContext) -> [Ingredient] {
        names.map { name in
            let ingredient = Ingredient(name: name, unit: "g")
            context.insert(ingredient)
            return ingredient
        }
    }

    // MARK: - Progress

    @Test func progressText_FirstStep_ShowsOneOfTotal() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil", "Coconut Oil", "Lye"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)

        #expect(sut.position == 1)
        #expect(sut.total == 3)
        #expect(sut.progressText == "1 of 3")
        #expect(sut.currentIngredientName == "Olive Oil")
        #expect(sut.isLastStep == false)
        #expect(sut.isComplete == false)
    }

    @Test func currentForm_TargetsCurrentIngredient() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil", "Coconut Oil"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)

        #expect(sut.currentForm.ingredient.name == "Olive Oil")
    }

    // MARK: - Validity

    @Test func canCommit_EmptyQuantity_IsFalse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)

        #expect(sut.canCommit == false)
    }

    @Test func canCommit_PositiveQuantity_IsTrue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        sut.currentForm.quantityText = "500"

        #expect(sut.canCommit == true)
    }

    // MARK: - Commit & advance

    @Test func commitAndAdvance_PersistsPurchaseAndMovesToNext() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil", "Coconut Oil"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        sut.currentForm.quantityText = "500"
        sut.currentForm.totalPriceText = "10"
        try sut.commitAndAdvance(context: ctx)

        #expect(ingredients[0].purchases.count == 1)
        #expect(ingredients[0].purchases.first?.quantity == 500)
        #expect(sut.position == 2)
        #expect(sut.currentIngredientName == "Coconut Oil")
        #expect(sut.isLastStep == true)
        #expect(sut.isComplete == false)
    }

    @Test func commitAndAdvance_OnLastStep_MarksComplete() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        sut.currentForm.quantityText = "500"
        try sut.commitAndAdvance(context: ctx)

        #expect(ingredients[0].purchases.count == 1)
        #expect(sut.isComplete == true)
    }

    @Test func currentIngredientName_AfterCompletingQueue_StaysInBounds() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        sut.currentForm.quantityText = "500"
        try sut.commitAndAdvance(context: ctx)

        // index now runs one past the end; display accessors must not go out of bounds.
        #expect(sut.isComplete == true)
        #expect(sut.currentIngredientName == "Olive Oil")
        #expect(sut.progressText == "1 of 1")
    }

    // MARK: - Skip

    @Test func skip_DoesNotPersistAndAdvances() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil", "Coconut Oil"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        sut.skip(context: ctx)

        #expect(ingredients[0].purchases.isEmpty)
        #expect(sut.position == 2)
        #expect(sut.currentIngredientName == "Coconut Oil")
    }

    @Test func skip_OnLastStep_MarksComplete() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        sut.skip(context: ctx)

        #expect(ingredients[0].purchases.isEmpty)
        #expect(sut.isComplete == true)
    }

    // MARK: - Carry-over of shared fields

    @Test func commitAndAdvance_CarriesProviderAndDateToNextEntry() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let provider = Provider(name: "Soapery Co")
        ctx.insert(provider)
        let ingredients = makeIngredients(["Olive Oil", "Coconut Oil"], in: ctx)
        let purchaseDate = try #require(Calendar.current.date(byAdding: .day, value: -3, to: .now))

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        sut.currentForm.quantityText = "500"
        sut.currentForm.selectedProvider = provider
        sut.currentForm.dateOfPurchase = purchaseDate
        try sut.commitAndAdvance(context: ctx)

        #expect(sut.currentForm.selectedProvider === provider)
        #expect(sut.currentForm.dateOfPurchase == purchaseDate)
        // Per-item fields are not carried over.
        #expect(sut.currentForm.quantityText.isEmpty)
    }

    @Test func commitAndAdvance_DerivesJournalCodePerIngredientInsteadOfCarrying() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil", "Coconut Oil"], in: ctx)
        ingredients[0].code = "OLI"
        ingredients[1].code = "COC"

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        #expect(sut.currentForm.journalCode == "OLI-001")
        sut.currentForm.quantityText = "500"
        sut.currentForm.journalCode = "PO-42"
        try sut.commitAndAdvance(context: ctx)

        #expect(sut.currentForm.journalCode == "COC-001")
    }

    @Test func skip_StillCarriesPreviouslyCommittedProvider() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let provider = Provider(name: "Soapery Co")
        ctx.insert(provider)
        let ingredients = makeIngredients(["Olive Oil", "Coconut Oil", "Lye"], in: ctx)
        ingredients[2].code = "LYE"

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        sut.currentForm.quantityText = "500"
        sut.currentForm.selectedProvider = provider
        try sut.commitAndAdvance(context: ctx)   // -> Coconut Oil, carries provider
        sut.skip(context: ctx)                           // -> Lye, should still carry

        #expect(sut.currentIngredientName == "Lye")
        #expect(sut.currentForm.selectedProvider === provider)
        #expect(sut.currentForm.journalCode == "LYE-001")
    }

    // MARK: - Entries merged away mid-flow

    /// The queue captures every ingredient when the flow opens but builds each
    /// form only once it reaches that entry, so a later one can be merged away
    /// in between. It has to open on the survivor rather than on the row that
    /// was deleted.
    @Test func advance_LaterIngredientMergedAway_OpensTheSurvivor() throws {
        let (container, ctx) = try makeFullContext()
        _ = container
        let first = try installed("Olive Oil", slug: "olive-oil", uuid: 1, in: ctx)
        let keep = try installed("Coconut Oil", slug: "coconut-oil", uuid: 2, in: ctx)
        let captured = try installed("Coconut Oil", slug: "coconut-oil", uuid: 3, in: ctx)
        try ctx.save()

        let sut = BulkImportFlowViewModel(ingredients: [first, captured])
        try DuplicateMerger.mergeAll(in: ctx)
        #expect(captured.modelContext == nil)

        sut.currentForm.quantityText = "500"
        try sut.commitAndAdvance(context: ctx)

        #expect(sut.isComplete == false)
        #expect(sut.currentForm.ingredient.uuid == keep.uuid)
        #expect(sut.currentIngredientName == "Coconut Oil")
    }

    /// Nothing to resolve to, so the entry is passed over rather than opened:
    /// `PurchaseFormViewModel.init` reads the row's slug, which traps on a
    /// detached reference.
    @Test func advance_LaterIngredientDeletedWithNoSurvivor_IsPassedOver() throws {
        let (container, ctx) = try makeFullContext()
        _ = container
        let first = try installed("Olive Oil", slug: "olive-oil", uuid: 1, in: ctx)
        let doomed = try installed("Coconut Oil", slug: "coconut-oil", uuid: 2, in: ctx)
        let last = try installed("Lye", slug: "sodium-hydroxide", uuid: 3, in: ctx)
        try ctx.save()

        let sut = BulkImportFlowViewModel(ingredients: [first, doomed, last])
        ctx.delete(doomed)
        try ctx.save()

        sut.currentForm.quantityText = "500"
        try sut.commitAndAdvance(context: ctx)

        #expect(sut.isComplete == false)
        #expect(sut.currentForm.ingredient.uuid == last.uuid)
        #expect(sut.currentIngredientName == "Lye")
    }

    /// Every entry left in the queue is gone, so the flow finishes instead of
    /// presenting a form for a row that is no longer there. The progress label
    /// still reads, because the name was captured up front.
    @Test func advance_EveryRemainingIngredientDeleted_CompletesTheFlow() throws {
        let (container, ctx) = try makeFullContext()
        _ = container
        let first = try installed("Olive Oil", slug: "olive-oil", uuid: 1, in: ctx)
        let doomed = try installed("Coconut Oil", slug: "coconut-oil", uuid: 2, in: ctx)
        try ctx.save()

        let sut = BulkImportFlowViewModel(ingredients: [first, doomed])
        ctx.delete(doomed)
        try ctx.save()

        sut.skip(context: ctx)

        #expect(sut.isComplete == true)
        #expect(sut.currentIngredientName == "Coconut Oil")
    }
}
