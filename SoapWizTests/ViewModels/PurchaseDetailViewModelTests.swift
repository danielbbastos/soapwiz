import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("PurchaseDetailViewModel", .serialized)
@MainActor
struct PurchaseDetailViewModelTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private func makePurchase(quantity: Double, remaining: Double, in ctx: ModelContext) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            dateOfPurchase: .now, quantity: quantity, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
        purchase.remainingAmount = remaining
        ctx.insert(purchase)
        return purchase
    }

    @Test func adjustIncrements() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 100, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.adjust(by: 10)
        #expect(purchase.remainingAmount == 110)
    }

    @Test func adjustDecrements() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 100, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.adjust(by: -10)
        #expect(purchase.remainingAmount == 90)
    }

    @Test func adjustClampsToZero() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 5, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.adjust(by: -10)
        #expect(purchase.remainingAmount == 0)
    }

    @Test func adjustClampsToQuantity() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 495, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.adjust(by: 10)
        #expect(purchase.remainingAmount == 500)
    }

    @Test func commitEditParsesValidValue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 100, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.editingValue = "250"
        model.commitEdit()
        #expect(purchase.remainingAmount == 250)
        #expect(model.isEditingAmount == false)
    }

    @Test func commitEditClampsAboveQuantity() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 100, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.editingValue = "999"
        model.commitEdit()
        #expect(purchase.remainingAmount == 500)
    }

    @Test func commitEditClampsBelowZero() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 100, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.editingValue = "-50"
        model.commitEdit()
        #expect(purchase.remainingAmount == 0)
    }

    @Test func commitEditIgnoresInvalidInput() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 100, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.editingValue = "abc"
        model.commitEdit()
        #expect(purchase.remainingAmount == 100)
        #expect(model.isEditingAmount == false)
    }

    @Test func startEditingPopulatesValue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 123.5, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.startEditing()
        #expect(model.isEditingAmount == true)
        #expect(model.editingValue == (123.5).formatted(.number.precision(.fractionLength(0...2)).grouping(.never)))
    }

    @Test func isDirtyAfterAdjust() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 100, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        #expect(model.isDirty == false)
        model.adjust(by: 10)
        #expect(model.isDirty == true)
    }

    @Test func undoRestoresOriginalAmount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 100, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.adjust(by: 10)
        model.adjust(by: 10)
        model.undo()
        #expect(purchase.remainingAmount == 100)
        #expect(model.isDirty == false)
    }

    @Test func isDirtyWhenOpeningDateAutoSetButAmountRestored() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 500, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.adjust(by: -10)
        model.adjust(by: 10)
        #expect(purchase.remainingAmount == 500)
        #expect(purchase.openingDate != nil)
        #expect(model.isDirty == true)
    }

    @Test func autoSetOpeningDateOnAdjust() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 500, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.adjust(by: -10)
        #expect(purchase.openingDate != nil)
    }

    @Test func autoSetOpeningDateOnCommitEdit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 500, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.editingValue = "400"
        model.commitEdit()
        #expect(purchase.openingDate != nil)
    }

    @Test func openingDateNotOverwrittenIfAlreadySet() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 500, in: ctx)
        let existingDate = try #require(Calendar.current.date(byAdding: .day, value: -5, to: .now))
        purchase.openingDate = existingDate
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.adjust(by: -10)
        #expect(purchase.openingDate == existingDate)
    }

    @Test func openingDateNotSetWhenAtFullQuantity() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 490, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.adjust(by: 10)
        #expect(purchase.openingDate == nil)
    }

    @Test func openingDateClearedOnUndoWhenAutoSet() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 500, in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.adjust(by: -10)
        #expect(purchase.openingDate != nil)
        model.undo()
        #expect(purchase.remainingAmount == 500)
        #expect(purchase.openingDate == nil)
    }

    @Test func openingDateNotClearedOnUndoWhenAlreadySet() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(quantity: 500, remaining: 500, in: ctx)
        let existingDate = try #require(Calendar.current.date(byAdding: .day, value: -5, to: .now))
        purchase.openingDate = existingDate
        let model = PurchaseDetailViewModel(purchase: purchase)
        model.adjust(by: -10)
        model.undo()
        #expect(purchase.openingDate == existingDate)
    }
}

/// The remaining-amount edit reads in the user's locale (SW-179).
@Suite("PurchaseDetailViewModel — locale", .serialized)
@MainActor
struct PurchaseDetailViewModelLocaleTests {

    private func makePurchase(in ctx: ModelContext, quantity: Double = 5000, remaining: Double = 100) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            dateOfPurchase: .now, quantity: quantity, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
        purchase.remainingAmount = remaining
        ctx.insert(purchase)
        return purchase
    }

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    @Test func commitEdit_EnglishGroupedThousands_ReadsAsThousands() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase, locale: Locale(identifier: "en_US"))

        model.editingValue = "1,500"
        model.commitEdit()

        #expect(purchase.remainingAmount == 1500)
    }

    @Test func commitEdit_PortugueseDecimalComma_ReadsAsDecimal() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase, locale: Locale(identifier: "pt_PT"))

        model.editingValue = "12,5"
        model.commitEdit()

        #expect(purchase.remainingAmount == 12.5)
    }

    @Test func startEditing_PrefillsInTheLocale_AndCommitsUnchanged() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(in: ctx, remaining: 1234.5)
        let germany = Locale(identifier: "de_DE")
        let model = PurchaseDetailViewModel(purchase: purchase, locale: germany)

        model.startEditing()
        model.commitEdit()

        #expect(model.editingValue == 1234.5.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(germany)))
        #expect(purchase.remainingAmount == 1234.5)
    }

    @Test func commitEdit_Unreadable_KeepsTheStoredAmount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = makePurchase(in: ctx)
        let model = PurchaseDetailViewModel(purchase: purchase, locale: Locale(identifier: "en_US"))

        model.editingValue = "1.2.3"
        model.commitEdit()

        #expect(purchase.remainingAmount == 100)
    }
}
