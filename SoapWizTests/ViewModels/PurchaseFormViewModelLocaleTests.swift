import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The purchase form reads and pre-fills numbers in the user's locale
/// (SW-179). It used to pre-fill in POSIX, showing "1.5" to a Portuguese user.
@Suite("PurchaseFormViewModel – locale", .serialized)
@MainActor
struct PurchaseFormViewModelLocaleTests {

    private let portugal = Locale(identifier: "pt_PT")
    private let unitedStates = Locale(identifier: "en_US")

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
    }

    private func purchase(quantity: Double, totalPrice: Double, in ctx: ModelContext) -> (Ingredient, IngredientPurchase) {
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: quantity,
            totalPrice: totalPrice,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        ctx.insert(purchase)
        ingredient.purchases.append(purchase)
        return (ingredient, purchase)
    }

    @Test func quantity_EnglishGroupedThousands_ReadsAsThousands() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let model = PurchaseFormViewModel(ingredient: ingredient, locale: unitedStates)

        model.quantityText = "1,500"
        model.totalPriceText = "12.50"

        #expect(model.quantity == 1500)
        #expect(model.totalPrice == 12.5)
    }

    @Test func quantity_PortugueseDecimalComma_ReadsAsDecimal() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let model = PurchaseFormViewModel(ingredient: ingredient, locale: portugal)

        model.quantityText = "1,5"
        model.totalPriceText = "12,50"

        #expect(model.quantity == 1.5)
        #expect(model.totalPrice == 12.5)
    }

    @Test func quantity_Unreadable_IsZeroAndInvalid() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let model = PurchaseFormViewModel(ingredient: ingredient, locale: unitedStates)

        model.quantityText = "1.2.3"

        #expect(model.quantity == 0)
        #expect(!model.isValid)
    }

    @Test func editing_PrefillsInTheLocale_AndReadsBackTheSameValues() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (ingredient, stored) = purchase(quantity: 1234.5, totalPrice: 19.99, in: ctx)

        let model = PurchaseFormViewModel(ingredient: ingredient, purchase: stored, locale: portugal)

        let expected = FloatingPointFormatStyle<Double>(locale: portugal).precision(.fractionLength(0...2)).grouping(.never)
        #expect(model.quantityText == 1234.5.formatted(expected))
        #expect(model.totalPriceText == 19.99.formatted(expected))
        #expect(model.quantity == 1234.5)
        #expect(model.totalPrice == 19.99)
        #expect(!model.isDirty)
    }

    @Test func editing_SavingUnchangedPrefill_KeepsTheStoredValues() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (ingredient, stored) = purchase(quantity: 1.5, totalPrice: 1500, in: ctx)
        let model = PurchaseFormViewModel(ingredient: ingredient, purchase: stored, locale: portugal)

        try model.save(context: ctx)

        #expect(stored.quantity == 1.5)
        #expect(stored.totalPrice == 1500)
    }
}
