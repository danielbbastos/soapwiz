import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientForm – sap & density", .serialized)
@MainActor
struct IngredientFormFieldTests: IngredientFormTestHelpers {

    @Test func showsSapValue_OilsCategory_ReturnsTrue() {
        let model = IngredientFormViewModel()
        model.selectedCategory = IngredientCategory(name: IngredientCategory.Name.oils)
        #expect(model.showsSapValue)
    }
    @Test func showsSapValue_WaxesCategory_ReturnsTrue() {
        let model = IngredientFormViewModel()
        model.selectedCategory = IngredientCategory(name: IngredientCategory.Name.waxes)
        #expect(model.showsSapValue)
    }
    @Test func showsSapValue_FatsCategory_ReturnsTrue() {
        let model = IngredientFormViewModel()
        model.selectedCategory = IngredientCategory(name: IngredientCategory.Name.fats)
        #expect(model.showsSapValue)
    }
    @Test func showsSapValue_AdditivesCategory_ReturnsFalse() {
        let model = IngredientFormViewModel()
        model.selectedCategory = IngredientCategory(name: IngredientCategory.Name.additives)
        #expect(!model.showsSapValue)
    }
    @Test func showsSapValue_NoCategory_ReturnsFalse() {
        let model = IngredientFormViewModel()
        #expect(!model.showsSapValue)
    }
    @Test func showsDensity_MillilitersUnit_ReturnsTrue() {
        let model = IngredientFormViewModel()
        model.selectedUnit = .milliliters
        #expect(model.showsDensity)
    }
    @Test func showsDensity_LitersUnit_ReturnsTrue() {
        let model = IngredientFormViewModel()
        model.selectedUnit = .liters
        #expect(model.showsDensity)
    }
    @Test func showsDensity_GramsUnit_ReturnsFalse() {
        let model = IngredientFormViewModel()
        model.selectedUnit = .grams
        #expect(!model.showsDensity)
    }
    @Test func showsDensity_NoUnit_ReturnsFalse() {
        let model = IngredientFormViewModel()
        #expect(!model.showsDensity)
    }
    @Test func saveSapValue_PersistsValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let cat = IngredientCategory(name: "Oils")
        ctx.insert(cat)

        let model = IngredientFormViewModel()
        model.name = "Olive Oil"
        model.selectedUnit = .grams
        model.selectedCategory = cat
        model.sapValue = "0.134"
        let ingredient = try #require(model.save(context: ctx))
        #expect(ingredient.sapValue == 0.134)
    }
    @Test func saveSapValue_EmptyString_StoresNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oilsCategory = IngredientCategory(name: "Oils")
        ctx.insert(oilsCategory)

        let model = IngredientFormViewModel()
        model.name = "Olive Oil"
        model.selectedUnit = .grams
        model.selectedCategory = oilsCategory
        model.sapValue = ""
        let ingredient = try #require(model.save(context: ctx))
        #expect(ingredient.sapValue == nil)
    }
    @Test func populatesSapValueWhenEditing() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        existing.sapValue = 0.134
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        let parsed = Double(model.sapValue.replacingOccurrences(of: ",", with: "."))
        #expect(parsed == 0.134)
    }
    @Test func saveDensity_PersistsValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let model = IngredientFormViewModel()
        model.name = "Olive Oil"
        model.selectedUnit = .milliliters
        model.density = "0.916"
        let ingredient = try #require(model.save(context: ctx))
        #expect(ingredient.density == 0.916)
    }
    @Test func saveDensity_EmptyString_StoresNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let model = IngredientFormViewModel()
        model.name = "Olive Oil"
        model.selectedUnit = .milliliters
        model.density = ""
        let ingredient = try #require(model.save(context: ctx))
        #expect(ingredient.density == nil)
    }
    @Test func populatesDensityWhenEditing() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        existing.density = 0.916
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        let parsed = Double(model.density.replacingOccurrences(of: ",", with: "."))
        #expect(parsed == 0.916)
    }
}
