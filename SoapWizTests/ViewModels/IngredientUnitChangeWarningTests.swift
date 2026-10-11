import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The form warns when a unit change can't convert, so stock and the low-stock
/// level keep their numbers (SW-256).
@Suite("Ingredient unit change — warning", .serialized)
@MainActor
struct IngredientUnitChangeWarningTests: IngredientUnitChangeTestHelpers {

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
