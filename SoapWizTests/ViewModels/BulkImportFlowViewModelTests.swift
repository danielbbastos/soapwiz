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
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return (container, container.mainContext)
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
        #expect(sut.currentIngredient.name == "Olive Oil")
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
        sut.commitAndAdvance(context: ctx)

        #expect(ingredients[0].purchases.count == 1)
        #expect(ingredients[0].purchases.first?.quantity == 500)
        #expect(sut.position == 2)
        #expect(sut.currentIngredient.name == "Coconut Oil")
        #expect(sut.isLastStep == true)
        #expect(sut.isComplete == false)
    }

    @Test func commitAndAdvance_OnLastStep_MarksComplete() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        sut.currentForm.quantityText = "500"
        sut.commitAndAdvance(context: ctx)

        #expect(ingredients[0].purchases.count == 1)
        #expect(sut.isComplete == true)
    }

    @Test func currentIngredient_AfterCompletingQueue_StaysInBounds() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        sut.currentForm.quantityText = "500"
        sut.commitAndAdvance(context: ctx)

        // index now runs one past the end; display accessors must not go out of bounds.
        #expect(sut.isComplete == true)
        #expect(sut.currentIngredient.name == "Olive Oil")
        #expect(sut.progressText == "1 of 1")
    }

    // MARK: - Skip

    @Test func skip_DoesNotPersistAndAdvances() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil", "Coconut Oil"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        sut.skip()

        #expect(ingredients[0].purchases.isEmpty)
        #expect(sut.position == 2)
        #expect(sut.currentIngredient.name == "Coconut Oil")
    }

    @Test func skip_OnLastStep_MarksComplete() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = makeIngredients(["Olive Oil"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        sut.skip()

        #expect(ingredients[0].purchases.isEmpty)
        #expect(sut.isComplete == true)
    }

    // MARK: - Carry-over of shared fields

    @Test func commitAndAdvance_CarriesProviderDateAndJournalToNextEntry() throws {
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
        sut.currentForm.journalCode = "PO-42"
        sut.commitAndAdvance(context: ctx)

        #expect(sut.currentForm.selectedProvider === provider)
        #expect(sut.currentForm.dateOfPurchase == purchaseDate)
        #expect(sut.currentForm.journalCode == "PO-42")
        // Per-item fields are not carried over.
        #expect(sut.currentForm.quantityText.isEmpty)
    }

    @Test func skip_StillCarriesPreviouslyCommittedSharedFields() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let provider = Provider(name: "Soapery Co")
        ctx.insert(provider)
        let ingredients = makeIngredients(["Olive Oil", "Coconut Oil", "Lye"], in: ctx)

        let sut = BulkImportFlowViewModel(ingredients: ingredients)
        sut.currentForm.quantityText = "500"
        sut.currentForm.selectedProvider = provider
        sut.currentForm.journalCode = "PO-42"
        sut.commitAndAdvance(context: ctx)   // -> Coconut Oil, carries provider/journal
        sut.skip()                           // -> Lye, should still carry

        #expect(sut.currentIngredient.name == "Lye")
        #expect(sut.currentForm.selectedProvider === provider)
        #expect(sut.currentForm.journalCode == "PO-42")
    }
}
