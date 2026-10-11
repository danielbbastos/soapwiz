import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Changing an ingredient's unit to another of the same kind converts its stock
/// instead of relabelling it (SW-256).
@Suite("Ingredient unit change", .serialized)
@MainActor
struct IngredientUnitChangeTests {

    private let locale = Locale(identifier: "en_US_POSIX")

    private func makeContainer() throws -> ModelContainer {
        let schema = ModelContainerFactory.schema
        return try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
    }

    private func makePurchase(quantity: Double, totalPrice: Double = 10, remaining: Double? = nil) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: quantity,
            totalPrice: totalPrice,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        if let remaining { purchase.remainingAmount = remaining }
        return purchase
    }

    private func makeIngredient(
        in context: ModelContext,
        unit: String,
        quantities: [Double] = [],
        threshold: Double? = nil
    ) throws -> Ingredient {
        let ingredient = Ingredient(name: "Olive Oil", unit: unit)
        ingredient.lowStockThreshold = threshold
        context.insert(ingredient)
        for quantity in quantities {
            let purchase = makePurchase(quantity: quantity)
            context.insert(purchase)
            purchase.attach(to: ingredient)
        }
        try context.save()
        return ingredient
    }

    private func approximately(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 1e-9
    }

    // MARK: Converter

    @Test func convertSameKind_VolumeBothWays_Converts() throws {
        let toLiters = try #require(IngredientUnitConverter.convertSameKind(2500, from: "ml", to: "L"))
        let toMilliliters = try #require(IngredientUnitConverter.convertSameKind(2.5, from: "L", to: "ml"))
        #expect(approximately(toLiters, 2.5))
        #expect(approximately(toMilliliters, 2500))
    }

    @Test func convertSameKind_Mass_Converts() throws {
        let kilograms = try #require(IngredientUnitConverter.convertSameKind(1500, from: "g", to: "kg"))
        let grams = try #require(IngredientUnitConverter.convertSameKind(1.5, from: "kg", to: "g"))
        let pounds = try #require(IngredientUnitConverter.convertSameKind(16, from: "oz", to: "lb"))
        #expect(approximately(kilograms, 1.5))
        #expect(approximately(grams, 1500))
        #expect(approximately(pounds, 1))
    }

    @Test func convertSameKind_SameSymbol_ReturnsAmount() {
        #expect(IngredientUnitConverter.convertSameKind(7, from: "L", to: "L") == 7)
        #expect(IngredientUnitConverter.convertSameKind(7, from: "g", to: "g") == 7)
    }

    @Test func convertSameKind_AcrossKinds_ReturnsNil() {
        #expect(IngredientUnitConverter.convertSameKind(100, from: "g", to: "ml") == nil)
        #expect(IngredientUnitConverter.convertSameKind(100, from: "L", to: "kg") == nil)
    }

    @Test func convertSameKind_CountOrUnknown_ReturnsNil() {
        #expect(IngredientUnitConverter.convertSameKind(5, from: "un", to: "un") == nil)
        #expect(IngredientUnitConverter.convertSameKind(5, from: "un", to: "g") == nil)
        #expect(IngredientUnitConverter.convertSameKind(5, from: "", to: "g") == nil)
        #expect(IngredientUnitConverter.convertSameKind(5, from: "g", to: "") == nil)
        #expect(IngredientUnitConverter.convertSameKind(5, from: "", to: "") == nil)
    }

    // MARK: Model

    @Test func changeUnit_MillilitersToLiters_ConvertsStockAndKeepsPrice() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "ml", quantities: [10_000, 10_500])
        let purchases = ingredient.purchases.sorted { $0.quantity < $1.quantity }
        purchases[0].remainingAmount = 4000
        let priceBefore = purchases.map(\.pricePerUnit)

        ingredient.changeUnit(to: "L")

        #expect(ingredient.unit == "L")
        #expect(approximately(ingredient.totalRemaining, 4 + 10.5))
        let after = ingredient.purchases.sorted { $0.quantity > $1.quantity }
        #expect(approximately(after[0].quantity, 10.5))
        #expect(approximately(after[1].quantity, 10))
        #expect(approximately(after[1].remainingAmount, 4))
        #expect(after.allSatisfy { $0.totalPrice == 10 })
        #expect(approximately(after[0].pricePerUnit, priceBefore[1] * 1000))
        #expect(approximately(after[1].pricePerUnit, priceBefore[0] * 1000))
    }

    @Test func changeUnit_TwentyThousandFiveHundredMilliliters_BecomesTwentyPointFiveLiters() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "ml", quantities: [20_500])

        ingredient.changeUnit(to: "L")

        #expect(approximately(ingredient.totalRemaining, 20.5))
    }

    @Test func changeUnit_RoundTrip_RestoresOriginalValues() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "L", quantities: [1.234, 0.5])
        let purchase = try #require(ingredient.purchases.first { $0.quantity == 1.234 })
        purchase.remainingAmount = 0.3

        ingredient.changeUnit(to: "ml")
        ingredient.changeUnit(to: "L")

        #expect(ingredient.unit == "L")
        #expect(approximately(purchase.quantity, 1.234))
        #expect(approximately(purchase.remainingAmount, 0.3))
    }

    @Test func changeUnit_AcrossKinds_OnlyRelabels() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "g", quantities: [500])

        ingredient.changeUnit(to: "ml")

        #expect(ingredient.unit == "ml")
        #expect(ingredient.totalRemaining == 500)
        #expect(try #require(ingredient.purchases.first).quantity == 500)
    }

    @Test func changeUnit_FromBlankUnit_OnlyRelabels() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "", quantities: [3])

        ingredient.changeUnit(to: "kg")

        #expect(ingredient.unit == "kg")
        #expect(ingredient.totalRemaining == 3)
    }

    @Test func changeUnit_LeavesBatchLineItemUntouched() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "ml", quantities: [2000])
        let lineItem = BatchLineItem(
            ingredient: ingredient,
            ingredientName: "Olive Oil",
            amountConsumed: 500,
            unit: "ml",
            cost: 2,
            draws: []
        )
        context.insert(lineItem)
        try context.save()

        ingredient.changeUnit(to: "L")

        #expect(lineItem.amountConsumed == 500)
        #expect(lineItem.unit == "ml")
    }

    // MARK: Form

    @Test func selectedUnit_SameKind_ConvertsThresholdText() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "ml", quantities: [5000], threshold: 1500)
        let model = IngredientFormViewModel(ingredient: ingredient, locale: locale)

        model.selectedUnit = .liters

        #expect(LocaleDecimal.parse(model.lowStockThreshold, locale: locale) == 1.5)
    }

    @Test func selectedUnit_ChangedBack_RestoresThresholdText() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "kg", quantities: [5], threshold: 1.234)
        let model = IngredientFormViewModel(ingredient: ingredient, locale: locale)
        let original = model.lowStockThreshold

        model.selectedUnit = .grams
        #expect(LocaleDecimal.parse(model.lowStockThreshold, locale: locale) == 1234)
        model.selectedUnit = .kilograms

        #expect(model.lowStockThreshold == original)
    }

    @Test func save_ConvertedThreshold_SurvivesReopeningAndResaving() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "g", quantities: [5000], threshold: 1234)
        let converting = IngredientFormViewModel(ingredient: ingredient, locale: locale)
        converting.selectedUnit = .kilograms
        converting.save(context: context)

        let reopened = IngredientFormViewModel(ingredient: ingredient, locale: locale)
        reopened.name = "Renamed Oil"
        reopened.save(context: context)

        #expect(approximately(try #require(ingredient.lowStockThreshold), 1.234))
    }

    @Test func selectedUnit_AcrossKinds_LeavesThresholdText() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "g", quantities: [500], threshold: 100)
        let model = IngredientFormViewModel(ingredient: ingredient, locale: locale)
        let original = model.lowStockThreshold

        model.selectedUnit = .milliliters

        #expect(model.lowStockThreshold == original)
    }

    @Test func selectedUnit_UnreadableOrEmptyThreshold_IsLeftAlone() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "ml", quantities: [500])
        let model = IngredientFormViewModel(ingredient: ingredient, locale: locale)

        model.selectedUnit = .liters
        #expect(model.lowStockThreshold.isEmpty)

        model.lowStockThreshold = "1,2,3"
        model.selectedUnit = .milliliters
        #expect(model.lowStockThreshold == "1,2,3")
    }

    @Test func save_SameKindUnitChange_ConvertsStockAndThresholdWithoutChangingLowStock() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "ml", quantities: [1000], threshold: 1500)
        let wasLowStock = ingredient.isLowStock
        let model = IngredientFormViewModel(ingredient: ingredient, locale: locale)

        model.selectedUnit = .liters
        model.save(context: context)

        #expect(ingredient.unit == "L")
        #expect(approximately(try #require(ingredient.lowStockThreshold), 1.5))
        #expect(approximately(ingredient.totalRemaining, 1))
        #expect(ingredient.isLowStock == wasLowStock)
    }

    @Test func save_AcrossKindsUnitChange_KeepsNumbers() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "g", quantities: [500], threshold: 100)
        let model = IngredientFormViewModel(ingredient: ingredient, locale: locale)

        model.selectedUnit = .milliliters
        model.save(context: context)

        #expect(ingredient.unit == "ml")
        #expect(ingredient.totalRemaining == 500)
        #expect(ingredient.lowStockThreshold == 100)
    }

    // MARK: Warning flag

    @Test func unitChangeKeepsAmounts_AcrossKinds_IsTrue() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "g", quantities: [500])
        let model = IngredientFormViewModel(ingredient: ingredient, locale: locale)

        model.selectedUnit = .milliliters

        #expect(model.unitChangeKeepsAmounts)
    }

    @Test func unitChangeKeepsAmounts_ToCountOrNone_IsTrue() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "g", quantities: [500])
        let model = IngredientFormViewModel(ingredient: ingredient, locale: locale)

        model.selectedUnit = .units
        #expect(model.unitChangeKeepsAmounts)
        model.selectedUnit = nil
        #expect(model.unitChangeKeepsAmounts)
    }

    @Test func unitChangeKeepsAmounts_ThresholdOnly_IsTrue() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "g", threshold: 100)
        let model = IngredientFormViewModel(ingredient: ingredient, locale: locale)

        model.selectedUnit = .milliliters

        #expect(model.unitChangeKeepsAmounts)
    }

    @Test func unitChangeKeepsAmounts_NothingToKeep_IsFalse() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "g")
        let model = IngredientFormViewModel(ingredient: ingredient, locale: locale)

        model.selectedUnit = .milliliters

        #expect(!model.unitChangeKeepsAmounts)
    }

    @Test func unitChangeKeepsAmounts_SameKind_IsFalse() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "g", quantities: [500], threshold: 100)
        let model = IngredientFormViewModel(ingredient: ingredient, locale: locale)

        model.selectedUnit = .kilograms

        #expect(!model.unitChangeKeepsAmounts)
    }

    @Test func unitChangeKeepsAmounts_UnitUnchanged_IsFalse() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ingredient = try makeIngredient(in: context, unit: "g", quantities: [500], threshold: 100)
        let model = IngredientFormViewModel(ingredient: ingredient, locale: locale)

        #expect(!model.unitChangeKeepsAmounts)
    }

    @Test func unitChangeKeepsAmounts_NewIngredient_IsFalse() {
        let model = IngredientFormViewModel(locale: locale)

        model.selectedUnit = .grams

        #expect(!model.unitChangeKeepsAmounts)
    }
}
