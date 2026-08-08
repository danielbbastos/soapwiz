import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeForm – ingredients", .serialized)
@MainActor
struct RecipeFormIngredientsTests: RecipeFormTestHelpers {

    @Test func addAdditive_PreventsDuplicates() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Salt", unit: "g")
        ctx.insert(ingredient)

        let model = RecipeFormViewModel()
        model.addAdditive(ingredient)
        model.addAdditive(ingredient)

        #expect(model.additiveDrafts.count == 1)
    }
    @Test func removeAdditive_RemovesAtIndex() {
        let model = RecipeFormViewModel()
        model.addAdditive(Ingredient(name: "Salt"))
        model.addAdditive(Ingredient(name: "Clay"))

        model.removeAdditive(at: IndexSet(integer: 0))

        #expect(model.additiveDrafts.count == 1)
        #expect(model.additiveDrafts[0].ingredient.name == "Clay")
    }
    @Test func updateAdditive_Amount() {
        let model = RecipeFormViewModel()
        model.addAdditive(Ingredient(name: "Salt"))
        let id = model.additiveDrafts[0].id

        model.updateAdditive(id: id, amount: 5)

        #expect(model.additiveDrafts[0].amount == 5)
    }
    @Test func updateAdditive_Unit() {
        let model = RecipeFormViewModel()
        model.addAdditive(Ingredient(name: "Salt"))
        let id = model.additiveDrafts[0].id

        model.updateAdditive(id: id, unit: "ml")

        #expect(model.additiveDrafts[0].unit == "ml")
    }
    @Test func addFragrance_PreventsDuplicates() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Lavender EO", unit: "ml")
        ctx.insert(ingredient)

        let model = RecipeFormViewModel()
        model.addFragrance(ingredient)
        model.addFragrance(ingredient)

        #expect(model.fragranceDrafts.count == 1)
    }
    @Test func removeFragrance_RemovesAtIndex() {
        let model = RecipeFormViewModel()
        model.addFragrance(Ingredient(name: "Lavender EO"))
        model.addFragrance(Ingredient(name: "Rose EO"))

        model.removeFragrance(at: IndexSet(integer: 0))

        #expect(model.fragranceDrafts.count == 1)
        #expect(model.fragranceDrafts[0].ingredient.name == "Rose EO")
    }
    @Test func userEditedFragrance_Amount() {
        let model = RecipeFormViewModel()
        model.addFragrance(Ingredient(name: "Lavender EO"))
        let id = model.fragranceDrafts[0].id

        model.userEditedFragrance(id: id, amount: 10)

        #expect(model.fragranceDrafts[0].amount == 10)
    }
    @Test func setFragranceUnit_StampsEveryDraft() {
        let model = RecipeFormViewModel()
        model.addFragrance(Ingredient(name: "Lavender EO"))
        model.addFragrance(Ingredient(name: "Rose EO"))

        model.setFragranceUnit(.grams)

        #expect(model.fragranceUnit == .grams)
        #expect(model.fragranceDrafts.allSatisfy { $0.unit == "g" })
    }
    @Test func save_AdditiveAndFragrance_RoundTrip() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let additive = Ingredient(name: "Salt", unit: "g")
        ctx.insert(additive)
        let fragrance = Ingredient(name: "Lavender EO", unit: "ml")
        ctx.insert(fragrance)

        let model = RecipeFormViewModel()
        model.name = "Test"
        model.addAdditive(additive)
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 5, unit: "g")
        model.setFragranceUnit(.milliliters)
        model.addFragrance(fragrance)
        model.userEditedFragrance(id: model.fragranceDrafts[0].id, amount: 10)
        let recipe = model.save(context: ctx)
        _ = recipe

        let allRI = try ctx.fetch(FetchDescriptor<RecipeIngredient>())
        #expect(allRI.count == 2)
        let savedAdditive = allRI.first { $0.ingredientRole == .additive }
        let savedFragrance = allRI.first { $0.ingredientRole == .fragrance }
        #expect(savedAdditive?.additiveAmount == 5)
        #expect(savedAdditive?.additiveUnit == "g")
        #expect(savedFragrance?.additiveAmount == 10)
        #expect(savedFragrance?.additiveUnit == "ml")
    }
    @Test func load_PopulatesAdditiveDrafts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Salt", unit: "g")
        ctx.insert(ingredient)
        let recipe = Recipe(name: "Test", desc: "")
        ctx.insert(recipe)
        let recipeIngredient = RecipeIngredient(ingredient: ingredient, percentage: 0, role: .additive)
        recipeIngredient.additiveAmount = 5
        recipeIngredient.additiveUnit = "g"
        recipeIngredient.recipe = recipe
        ctx.insert(recipeIngredient)

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.additiveDrafts.count == 1)
        #expect(model.additiveDrafts[0].ingredient.name == "Salt")
        #expect(model.additiveDrafts[0].amount == 5)
        #expect(model.additiveDrafts[0].unit == "g")
    }
    @Test func defaultFragranceUnit_PercentageMode_IsPercentageOfOils() {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        #expect(model.defaultFragranceUnit == .percentOfOils)
    }
    @Test func defaultFragranceUnit_AbsoluteMode_MatchesWeightUnit() {
        let model = RecipeFormViewModel()
        model.weightUnit = "oz"
        #expect(model.defaultFragranceUnit == .ounces)
    }
    @Test func defaultFragranceUnit_UnsupportedWeightUnit_FallsBackToGrams() {
        let model = RecipeFormViewModel()
        model.weightUnit = "kg"
        #expect(model.defaultFragranceUnit == .grams)
    }
    @Test func defaultAdditiveUnit_PercentageMode_IsGrams() {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        #expect(model.defaultAdditiveUnit == "g")
    }
    @Test func defaultAdditiveUnit_AbsoluteMode_MatchesWeightUnit() {
        let model = RecipeFormViewModel()
        model.weightUnit = "oz"
        #expect(model.defaultAdditiveUnit == "oz")
    }
    @Test func addAdditive_PercentageMode_DefaultsToGrams() {
        // Additives are weight-conventional, so they default to grams rather than
        // silently applying a percentage of the oils.
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.addAdditive(Ingredient(name: "Salt"))
        #expect(model.additiveDrafts[0].unit == "g")
    }
    @Test func addAdditive_AbsoluteMode_DefaultsToWeightUnit() {
        let model = RecipeFormViewModel()
        model.weightUnit = "oz"
        model.addAdditive(Ingredient(name: "Salt"))
        #expect(model.additiveDrafts[0].unit == "oz")
    }
    @Test func addFragrance_PercentageMode_DefaultsToPercentageOfOils() {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.addFragrance(Ingredient(name: "Lavender EO"))
        #expect(model.fragranceDrafts[0].unit == "% of oils")
    }
    @Test func addFragrance_AbsoluteMode_DefaultsToWeightUnit() {
        let model = RecipeFormViewModel()
        model.weightUnit = "oz"
        model.addFragrance(Ingredient(name: "Lavender EO"))
        #expect(model.fragranceDrafts[0].unit == "oz")
    }
    @Test func addFragrance_ExplicitUnitSet_KeepsItOverTheDefault() {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.setFragranceUnit(.grams)
        model.addFragrance(Ingredient(name: "Lavender EO"))
        #expect(model.fragranceDrafts[0].unit == "g")
    }
}
