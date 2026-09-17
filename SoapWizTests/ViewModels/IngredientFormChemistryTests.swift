import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Editing a library ingredient's chemistry is what turns it into a custom one.
/// Editing anything else — name, code, category, unit — must not, which means the
/// form has to leave chemistry it isn't showing alone rather than nulling it.
@Suite("IngredientFormViewModel — library chemistry", .serialized)
@MainActor
struct IngredientFormChemistryTests: IngredientFormTestHelpers {

    private func makeOilCategory() -> IngredientCategory {
        IngredientCategory(name: IngredientCategory.Name.oils)
    }

    /// An olive oil as the installer leaves it: sold by the millilitre, so the form
    /// shows both the SAP and the density field.
    private func makeLibraryOil(
        in context: ModelContext,
        unit: String = "ml"
    ) throws -> Ingredient {
        let ingredient = Ingredient(name: "Olive Oil", category: makeOilCategory(), unit: unit)
        ingredient.librarySlug = "olive-oil"
        ingredient.sapValue = 0.1345
        ingredient.density = 0.911
        context.insert(ingredient)
        try context.save()
        return ingredient
    }

    // MARK: - Chemistry edits make a row custom

    @Test func changesLibraryChemistry_SapEdited_IsTrue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let olive = try makeLibraryOil(in: ctx)

        let model = IngredientFormViewModel(ingredient: olive)
        model.sapValue = "0.2"

        #expect(model.changesLibraryChemistry)
    }

    @Test func save_SapEdited_SetsHasCustomChemistry() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let olive = try makeLibraryOil(in: ctx)

        let model = IngredientFormViewModel(ingredient: olive)
        model.sapValue = "0.2"
        model.save(context: ctx)

        #expect(olive.hasCustomChemistry)
        #expect(olive.sapValue == 0.2)
        #expect(olive.isPristineLibraryRow == false)
    }

    @Test func save_DensityEdited_SetsHasCustomChemistry() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let olive = try makeLibraryOil(in: ctx)

        let model = IngredientFormViewModel(ingredient: olive)
        model.density = "0.95"
        model.save(context: ctx)

        #expect(olive.hasCustomChemistry)
        #expect(olive.density == 0.95)
    }

    @Test func changesLibraryChemistry_SapCleared_IsTrue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let olive = try makeLibraryOil(in: ctx)

        let model = IngredientFormViewModel(ingredient: olive)
        model.sapValue = ""

        #expect(model.changesLibraryChemistry)
    }

    // MARK: - Everything else leaves it alone

    /// The regression guard for the whole design: opening a library row and saving it
    /// untouched must leave it exactly as the installer wrote it.
    @Test func save_UntouchedLibraryRow_StaysPristine() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let olive = try makeLibraryOil(in: ctx)

        let model = IngredientFormViewModel(ingredient: olive)
        #expect(model.changesLibraryChemistry == false)
        model.save(context: ctx)

        #expect(olive.hasCustomChemistry == false)
        #expect(olive.isPristineLibraryRow)
        #expect(olive.sapValue == 0.1345)
        #expect(olive.density == 0.911)
    }

    @Test func save_NameAndCodeEdited_LeavesItALibraryRow() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let olive = try makeLibraryOil(in: ctx)

        let model = IngredientFormViewModel(ingredient: olive)
        model.name = "Olive Oil (Pomace)"
        model.code = "OOP"
        #expect(model.changesLibraryChemistry == false)
        model.save(context: ctx)

        #expect(olive.hasCustomChemistry == false)
        #expect(olive.name == "Olive Oil (Pomace)")
    }

    /// Switching an oil from millilitres to grams takes the density field off screen.
    /// Density belongs to the substance, not to the unit it is bought in, so it has to
    /// survive — and the row must not be branded custom for a unit change.
    @Test func save_UnitChangedAwayFromVolume_PreservesDensity() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let olive = try makeLibraryOil(in: ctx)

        let model = IngredientFormViewModel(ingredient: olive)
        model.selectedUnit = .grams
        #expect(model.showsDensity == false)
        #expect(model.changesLibraryChemistry == false)
        model.save(context: ctx)

        #expect(olive.density == 0.911)
        #expect(olive.hasCustomChemistry == false)
        #expect(olive.unit == IngredientUnit.grams.rawValue)
    }

    /// The same for SAP, which is hidden by moving the row to a category that isn't
    /// an oil.
    @Test func save_CategoryChangedAwayFromOil_PreservesSapValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let olive = try makeLibraryOil(in: ctx)
        let additives = IngredientCategory(name: IngredientCategory.Name.additives)
        ctx.insert(additives)
        try ctx.save()

        let model = IngredientFormViewModel(ingredient: olive)
        model.selectedCategory = additives
        #expect(model.showsSapValue == false)
        #expect(model.changesLibraryChemistry == false)
        model.save(context: ctx)

        #expect(olive.sapValue == 0.1345)
        #expect(olive.hasCustomChemistry == false)
    }

    // MARK: - Rows the rule doesn't apply to

    @Test func changesLibraryChemistry_UserCreatedRow_IsFalse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let blend = Ingredient(name: "My Blend", category: makeOilCategory(), unit: "g")
        blend.sapValue = 0.13
        ctx.insert(blend)
        try ctx.save()

        let model = IngredientFormViewModel(ingredient: blend)
        model.sapValue = "0.2"

        #expect(model.changesLibraryChemistry == false)
        model.save(context: ctx)
        #expect(blend.sapValue == 0.2)
        #expect(blend.hasCustomChemistry == false)
    }

    @Test func changesLibraryChemistry_NewIngredient_IsFalse() {
        let model = IngredientFormViewModel()
        model.sapValue = "0.2"

        #expect(model.changesLibraryChemistry == false)
    }

    /// Once a row is the user's own it stays that way, even when a later edit touches
    /// nothing but the name.
    @Test func save_AlreadyCustomRow_StaysCustom() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let olive = try makeLibraryOil(in: ctx)
        olive.hasCustomChemistry = true
        try ctx.save()

        let model = IngredientFormViewModel(ingredient: olive)
        model.name = "My Olive Oil"
        model.save(context: ctx)

        #expect(olive.hasCustomChemistry)
    }
}
