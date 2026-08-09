import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientForm – unsaved changes", .serialized)
@MainActor
struct IngredientFormDirtyStateTests: IngredientFormTestHelpers {

    // MARK: - Baseline

    @Test func isDirty_NewFormUntouched_IsFalse() {
        let model = IngredientFormViewModel()

        #expect(model.isDirty == false)
    }

    @Test func isDirty_NewFormWithDefaultCategoryUntouched_IsFalse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let category = IngredientCategory(name: "Oils")
        ctx.insert(category)

        let model = IngredientFormViewModel(defaultCategory: category)

        #expect(model.isDirty == false)
    }

    @Test func isDirty_EditedIngredientUntouched_IsFalse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let category = IngredientCategory(name: "Oils")
        ctx.insert(category)
        let ingredient = Ingredient(name: "Olive Oil", category: category, unit: "g")
        ingredient.code = "OLI"
        ingredient.lowStockThreshold = 75.5
        ingredient.sapValue = 0.1345
        ingredient.density = 0.92
        ctx.insert(ingredient)

        let model = IngredientFormViewModel(ingredient: ingredient)

        #expect(model.isDirty == false)
    }

    @Test func isDirty_AfterPrefilledNameDerivesCode_IsFalseOnceRecaptured() {
        let model = IngredientFormViewModel(prefilledName: "Manteiga de Karité")
        model.applyNameChange(existingCodes: [])
        // The view derives the code in `.task`, after init, then re-baselines.
        model.captureSnapshot()

        #expect(model.code.isEmpty == false)
        #expect(model.isDirty == false)
    }

    // MARK: - Per-field changes

    @Test func isDirty_NameChanged_IsTrue() {
        let model = IngredientFormViewModel()
        model.name = "Olive Oil"

        #expect(model.isDirty)
    }

    @Test func isDirty_CodeChanged_IsTrue() {
        let model = IngredientFormViewModel()
        model.code = "OLI"

        #expect(model.isDirty)
    }

    @Test func isDirty_UnitChanged_IsTrue() {
        let model = IngredientFormViewModel()
        model.selectedUnit = .grams

        #expect(model.isDirty)
    }

    @Test func isDirty_CategoryChanged_IsTrue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let category = IngredientCategory(name: "Oils")
        ctx.insert(category)

        let model = IngredientFormViewModel()
        model.selectedCategory = category

        #expect(model.isDirty)
    }

    @Test func isDirty_CategoryClearedWhileEditing_IsTrue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let category = IngredientCategory(name: "Oils")
        ctx.insert(category)
        let ingredient = Ingredient(name: "Olive Oil", category: category, unit: "g")
        ctx.insert(ingredient)

        let model = IngredientFormViewModel(ingredient: ingredient)
        model.selectedCategory = nil

        #expect(model.isDirty)
    }

    @Test func isDirty_LowStockThresholdChanged_IsTrue() {
        let model = IngredientFormViewModel()
        model.lowStockThreshold = "100"

        #expect(model.isDirty)
    }

    @Test func isDirty_SapValueChanged_IsTrue() {
        let model = IngredientFormViewModel()
        model.sapValue = "0.134"

        #expect(model.isDirty)
    }

    @Test func isDirty_DensityChanged_IsTrue() {
        let model = IngredientFormViewModel()
        model.density = "0.92"

        #expect(model.isDirty)
    }

    // MARK: - Reverting

    @Test func isDirty_ChangeThenRevert_IsFalse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.code = "OLI"
        ctx.insert(ingredient)

        let model = IngredientFormViewModel(ingredient: ingredient)
        model.name = "Coconut Oil"
        #expect(model.isDirty)

        model.name = "Olive Oil"
        #expect(model.isDirty == false)
    }

    @Test func isDirty_CategoryChangeThenRevert_IsFalse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        let butters = IngredientCategory(name: "Butters")
        ctx.insert(oils)
        ctx.insert(butters)
        let ingredient = Ingredient(name: "Olive Oil", category: oils, unit: "g")
        ctx.insert(ingredient)

        let model = IngredientFormViewModel(ingredient: ingredient)
        model.selectedCategory = butters
        #expect(model.isDirty)

        model.selectedCategory = oils
        #expect(model.isDirty == false)
    }
}
