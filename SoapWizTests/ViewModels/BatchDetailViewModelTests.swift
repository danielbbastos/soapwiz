import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("BatchDetailViewModel")
@MainActor
struct BatchDetailViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, QuantityUnit.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func makeBatch(quantity: Double, remaining: Double, in ctx: ModelContext) -> IngredientBatch {
        let batch = IngredientBatch(
            dateOfPurchase: .now, quantity: quantity, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
        batch.remainingAmount = remaining
        ctx.insert(batch)
        return batch
    }

    @Test func adjustIncrements() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 100, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.adjust(by: 10)
        #expect(batch.remainingAmount == 110)
    }

    @Test func adjustDecrements() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 100, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.adjust(by: -10)
        #expect(batch.remainingAmount == 90)
    }

    @Test func adjustClampsToZero() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 5, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.adjust(by: -10)
        #expect(batch.remainingAmount == 0)
    }

    @Test func adjustClampsToQuantity() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 495, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.adjust(by: 10)
        #expect(batch.remainingAmount == 500)
    }

    @Test func commitEditParsesValidValue() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 100, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.editingValue = "250"
        model.commitEdit()
        #expect(batch.remainingAmount == 250)
        #expect(model.isEditingAmount == false)
    }

    @Test func commitEditClampsAboveQuantity() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 100, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.editingValue = "999"
        model.commitEdit()
        #expect(batch.remainingAmount == 500)
    }

    @Test func commitEditClampsBelowZero() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 100, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.editingValue = "-50"
        model.commitEdit()
        #expect(batch.remainingAmount == 0)
    }

    @Test func commitEditIgnoresInvalidInput() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 100, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.editingValue = "abc"
        model.commitEdit()
        #expect(batch.remainingAmount == 100)
        #expect(model.isEditingAmount == false)
    }

    @Test func startEditingPopulatesValue() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 123.5, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.startEditing()
        #expect(model.isEditingAmount == true)
        #expect(model.editingValue == "123.5")
    }

    @Test func isDirtyAfterAdjust() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 100, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        #expect(model.isDirty == false)
        model.adjust(by: 10)
        #expect(model.isDirty == true)
    }

    @Test func undoRestoresOriginalAmount() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 100, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.adjust(by: 10)
        model.adjust(by: 10)
        model.undo()
        #expect(batch.remainingAmount == 100)
        #expect(model.isDirty == false)
    }

    @Test func isDirtyWhenOpeningDateAutoSetButAmountRestored() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 500, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.adjust(by: -10)
        model.adjust(by: 10)
        #expect(batch.remainingAmount == 500)
        #expect(batch.openingDate != nil)
        #expect(model.isDirty == true)
    }

    @Test func autoSetOpeningDateOnAdjust() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 500, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.adjust(by: -10)
        #expect(batch.openingDate != nil)
    }

    @Test func autoSetOpeningDateOnCommitEdit() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 500, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.editingValue = "400"
        model.commitEdit()
        #expect(batch.openingDate != nil)
    }

    @Test func openingDateNotOverwrittenIfAlreadySet() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 500, in: ctx)
        let existingDate = Calendar.current.date(byAdding: .day, value: -5, to: .now)!
        batch.openingDate = existingDate
        let model = BatchDetailViewModel(batch: batch)
        model.adjust(by: -10)
        #expect(batch.openingDate == existingDate)
    }

    @Test func openingDateNotSetWhenAtFullQuantity() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 490, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.adjust(by: 10)
        #expect(batch.openingDate == nil)
    }

    @Test func openingDateClearedOnUndoWhenAutoSet() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 500, in: ctx)
        let model = BatchDetailViewModel(batch: batch)
        model.adjust(by: -10)
        #expect(batch.openingDate != nil)
        model.undo()
        #expect(batch.remainingAmount == 500)
        #expect(batch.openingDate == nil)
    }

    @Test func openingDateNotClearedOnUndoWhenAlreadySet() throws {
        let ctx = try makeContainer().mainContext
        let batch = makeBatch(quantity: 500, remaining: 500, in: ctx)
        let existingDate = Calendar.current.date(byAdding: .day, value: -5, to: .now)!
        batch.openingDate = existingDate
        let model = BatchDetailViewModel(batch: batch)
        model.adjust(by: -10)
        model.undo()
        #expect(batch.openingDate == existingDate)
    }
}
