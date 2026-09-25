import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The ingredient form reads its numbers in the user's locale, and refuses to
/// save text it can't read rather than wiping the stored value (SW-179).
@Suite("IngredientFormViewModel — locale", .serialized)
@MainActor
struct IngredientFormLocaleTests: IngredientFormTestHelpers {

    private let germany = Locale(identifier: "de_DE")
    private let unitedStates = Locale(identifier: "en_US")

    private func makeOil(in context: ModelContext, sap: Double? = nil) throws -> Ingredient {
        let ingredient = Ingredient(name: "Olive Oil", category: IngredientCategory(name: IngredientCategory.Name.oils), unit: "ml")
        ingredient.sapValue = sap
        context.insert(ingredient)
        try context.save()
        return ingredient
    }

    /// A German user typing a SAP value with the point, as SoapCalc prints it.
    /// Read as grouping, "0.134" would be 134 and multiply the lye a thousandfold.
    @Test func save_SapTypedWithPointInGermany_StoresTheDecimal() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oil = try makeOil(in: ctx)
        let model = IngredientFormViewModel(ingredient: oil, locale: germany)

        model.sapValue = "0.134"
        model.density = "0,92"
        model.save(context: ctx)

        #expect(oil.sapValue == 0.134)
        #expect(oil.density == 0.92)
    }

    @Test func editing_PrefillsInTheLocale_AndSavesTheSameValues() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oil = try makeOil(in: ctx, sap: 0.1345)
        oil.density = 0.911
        oil.lowStockThreshold = 1500

        let model = IngredientFormViewModel(ingredient: oil, locale: germany)

        let fieldFormat = FloatingPointFormatStyle<Double>(locale: germany).precision(.fractionLength(0...4)).grouping(.never)
        #expect(model.sapValue == 0.1345.formatted(fieldFormat))
        #expect(model.isValid)
        model.save(context: ctx)
        #expect(oil.sapValue == 0.1345)
        #expect(oil.density == 0.911)
        #expect(oil.lowStockThreshold == 1500)
    }

    @Test func isValid_UnreadableSap_BlocksSaveInsteadOfWipingIt() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oil = try makeOil(in: ctx, sap: 0.134)
        let model = IngredientFormViewModel(ingredient: oil, locale: unitedStates)

        model.sapValue = "0,13,5"

        #expect(!model.isValid)
    }

    @Test func isValid_UnreadableThreshold_BlocksSave() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oil = try makeOil(in: ctx)
        let model = IngredientFormViewModel(ingredient: oil, locale: unitedStates)

        model.lowStockThreshold = "1.2.3"

        #expect(!model.isValid)
    }

    @Test func isValid_EmptyNumericFields_AreAllowed() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oil = try makeOil(in: ctx)
        let model = IngredientFormViewModel(ingredient: oil, locale: unitedStates)

        model.sapValue = ""
        model.density = ""
        model.lowStockThreshold = ""

        #expect(model.isValid)
    }

    /// A field that isn't on screen is preserved, not parsed, so leftover text
    /// in it must not block saving.
    @Test func isValid_UnreadableHiddenDensity_DoesNotBlockSave() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oil = try makeOil(in: ctx)
        let model = IngredientFormViewModel(ingredient: oil, locale: unitedStates)
        model.density = "1.2.3"

        model.selectedUnit = .grams

        #expect(!model.showsDensity)
        #expect(model.isValid)
    }
}
