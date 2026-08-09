import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("PurchaseFormViewModel – journal code", .serialized)
@MainActor
struct PurchaseFormViewModelJournalCodeTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
    }

    private func makeIngredient(code: String, in context: ModelContext) -> Ingredient {
        let ingredient = Ingredient(name: "Manteiga de Karité", unit: "g")
        ingredient.code = code
        context.insert(ingredient)
        return ingredient
    }

    @discardableResult
    private func addPurchase(journalCode: String, to ingredient: Ingredient, in context: ModelContext) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: 500,
            totalPrice: 10,
            badge: "",
            journalCode: journalCode,
            expiryDate: nil,
            openingDate: nil
        )
        context.insert(purchase)
        ingredient.purchases.append(purchase)
        return purchase
    }

    // MARK: - Numbering

    @Test func suggestedJournalCode_NoPurchases_StartsAtOne() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "MKO", in: ctx)

        #expect(PurchaseFormViewModel.suggestedJournalCode(for: ingredient) == "MKO-001")
    }

    @Test func suggestedJournalCode_ConsecutivePurchases_ContinuesSequence() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "MKO", in: ctx)
        addPurchase(journalCode: "MKO-1", to: ingredient, in: ctx)
        addPurchase(journalCode: "MKO-2", to: ingredient, in: ctx)

        #expect(PurchaseFormViewModel.suggestedJournalCode(for: ingredient) == "MKO-003")
    }

    @Test func suggestedJournalCode_GapInSequence_UsesHighestPlusOne() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "MKO", in: ctx)
        addPurchase(journalCode: "MKO-1", to: ingredient, in: ctx)
        addPurchase(journalCode: "MKO-5", to: ingredient, in: ctx)

        #expect(PurchaseFormViewModel.suggestedJournalCode(for: ingredient) == "MKO-006")
    }

    @Test func suggestedJournalCode_NonConformingCodes_AreIgnored() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "MKO", in: ctx)
        addPurchase(journalCode: "LOTE-XYZ", to: ingredient, in: ctx)
        addPurchase(journalCode: "", to: ingredient, in: ctx)
        addPurchase(journalCode: "MKO-", to: ingredient, in: ctx)
        addPurchase(journalCode: "MKO-2b", to: ingredient, in: ctx)
        addPurchase(journalCode: "OTHER-9", to: ingredient, in: ctx)

        #expect(PurchaseFormViewModel.suggestedJournalCode(for: ingredient) == "MKO-001")
    }

    @Test func suggestedJournalCode_CustomCodeAmongNumbered_DoesNotStallSequence() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "MKO", in: ctx)
        addPurchase(journalCode: "MKO-1", to: ingredient, in: ctx)
        addPurchase(journalCode: "LOTE-XYZ", to: ingredient, in: ctx)

        #expect(PurchaseFormViewModel.suggestedJournalCode(for: ingredient) == "MKO-002")
    }

    @Test func suggestedJournalCode_LowercasedCode_CountsTowardSequence() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "MKO", in: ctx)
        addPurchase(journalCode: "mko-3", to: ingredient, in: ctx)

        #expect(PurchaseFormViewModel.suggestedJournalCode(for: ingredient) == "MKO-004")
    }

    // MARK: - Padding

    @Test func suggestedJournalCode_WiderExistingPadding_IsPreserved() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "MKO", in: ctx)
        addPurchase(journalCode: "MKO-0007", to: ingredient, in: ctx)

        #expect(PurchaseFormViewModel.suggestedJournalCode(for: ingredient) == "MKO-0008")
    }

    @Test func suggestedJournalCode_PastThreeDigits_StopsPadding() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "MKO", in: ctx)
        addPurchase(journalCode: "MKO-999", to: ingredient, in: ctx)

        #expect(PurchaseFormViewModel.suggestedJournalCode(for: ingredient) == "MKO-1000")
    }

    @Test func suggestedJournalCode_LeadingZerosDoNotInflateNumber() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "MKO", in: ctx)
        addPurchase(journalCode: "MKO-002", to: ingredient, in: ctx)
        addPurchase(journalCode: "MKO-10", to: ingredient, in: ctx)

        #expect(PurchaseFormViewModel.suggestedJournalCode(for: ingredient) == "MKO-011")
    }

    @Test func suggestedJournalCode_EmptyIngredientCode_SuggestsNothing() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "", in: ctx)
        addPurchase(journalCode: "-1", to: ingredient, in: ctx)

        #expect(PurchaseFormViewModel.suggestedJournalCode(for: ingredient).isEmpty)
    }

    // MARK: - Form prefill

    @Test func journalCode_NewPurchase_IsPrefilledWithSuggestion() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "MKO", in: ctx)
        addPurchase(journalCode: "MKO-1", to: ingredient, in: ctx)

        let model = PurchaseFormViewModel(ingredient: ingredient)

        #expect(model.journalCode == "MKO-002")
    }

    @Test func journalCode_NewPurchaseForUncodedIngredient_IsEmpty() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "", in: ctx)

        let model = PurchaseFormViewModel(ingredient: ingredient)

        #expect(model.journalCode.isEmpty)
    }

    @Test func journalCode_EditingExistingPurchase_KeepsStoredValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "MKO", in: ctx)
        let purchase = addPurchase(journalCode: "LOTE-XYZ", to: ingredient, in: ctx)

        let model = PurchaseFormViewModel(ingredient: ingredient, purchase: purchase)

        #expect(model.journalCode == "LOTE-XYZ")
        #expect(model.isDirty == false)
    }

    @Test func journalCode_PrefilledSuggestionIsSaved() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = makeIngredient(code: "MKO", in: ctx)

        let model = PurchaseFormViewModel(ingredient: ingredient)
        model.quantityText = "500"
        model.save(context: ctx)

        #expect(ingredient.purchases.first?.journalCode == "MKO-001")
        #expect(PurchaseFormViewModel.suggestedJournalCode(for: ingredient) == "MKO-002")
    }
}
