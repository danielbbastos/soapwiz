import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeFormViewModel", .serialized)
@MainActor
struct RecipeFormViewModelTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Recipe.self, RecipeIngredient.self, Ingredient.self, IngredientCategory.self, QuantityUnit.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return (container, container.mainContext)
    }

    @Test func emptyNameInvalid() {
        let model = RecipeFormViewModel()
        #expect(model.canSave == false)
    }

    @Test func whitespaceOnlyNameInvalid() {
        let model = RecipeFormViewModel()
        model.name = "   "
        #expect(model.canSave == false)
    }

    @Test func validNameAllowsSave() {
        let model = RecipeFormViewModel()
        model.name = "Shea Butter Bar"
        #expect(model.canSave == true)
    }

    @Test func saveInsertsTrimmedRecipe() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.name = "  Lavender Soap  "
        model.desc = "  A calming bar  "

        let recipe = model.save(context: ctx)

        #expect(recipe.name == "Lavender Soap")
        #expect(recipe.desc == "A calming bar")
        let all = try ctx.fetch(FetchDescriptor<Recipe>())
        #expect(all.count == 1)
    }

    @Test func addIngredientPreventsDuplicates() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let unit = QuantityUnit(name: "g", symbol: "g")
        ctx.insert(unit)
        let ingredient = Ingredient(name: "Shea Butter", unit: unit)
        ctx.insert(ingredient)

        let model = RecipeFormViewModel()
        model.addIngredient(ingredient)
        model.addIngredient(ingredient)

        #expect(model.ingredientDrafts.count == 1)
    }

    @Test func saveInsertsRecipeIngredients() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let unit = QuantityUnit(name: "g", symbol: "g")
        ctx.insert(unit)
        let ingredient = Ingredient(name: "Coconut Oil", unit: unit)
        ctx.insert(ingredient)

        let model = RecipeFormViewModel()
        model.name = "Test Recipe"
        model.addIngredient(ingredient)
        model.ingredientDrafts[0].percentage = "45"

        let recipe = model.save(context: ctx)

        #expect(recipe.ingredients.count == 1)
        #expect(recipe.ingredients[0].percentage == 45)
        let allRI = try ctx.fetch(FetchDescriptor<RecipeIngredient>())
        #expect(allRI.count == 1)
    }

    @Test func saveConvertsCommaDecimalSeparator() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let unit = QuantityUnit(name: "g", symbol: "g")
        ctx.insert(unit)
        let ingredient = Ingredient(name: "Olive Oil", unit: unit)
        ctx.insert(ingredient)

        let model = RecipeFormViewModel()
        model.name = "Test Recipe"
        model.addIngredient(ingredient)
        model.ingredientDrafts[0].percentage = "33,5"

        let recipe = model.save(context: ctx)

        #expect(recipe.ingredients[0].percentage == 33.5)
    }

    // MARK: - Percentage distribution

    @Test func addIngredient_First_Gets100Percent() {
        let model = RecipeFormViewModel()
        model.addIngredient(Ingredient(name: "Coconut Oil"))
        #expect(model.ingredientDrafts[0].percentage == model.formatPercentage(100))
    }

    @Test func addIngredient_Second_SplitsEqually() {
        let model = RecipeFormViewModel()
        model.addIngredient(Ingredient(name: "Coconut Oil"))
        model.addIngredient(Ingredient(name: "Olive Oil"))
        #expect(model.ingredientDrafts[0].percentage == model.formatPercentage(50))
        #expect(model.ingredientDrafts[1].percentage == model.formatPercentage(50))
    }

    @Test func addIngredient_Third_SplitsEqually() {
        let model = RecipeFormViewModel()
        model.addIngredient(Ingredient(name: "A"))
        model.addIngredient(Ingredient(name: "B"))
        model.addIngredient(Ingredient(name: "C"))
        let share = model.formatPercentage(100.0 / 3.0)
        #expect(model.ingredientDrafts[0].percentage == share)
        #expect(model.ingredientDrafts[1].percentage == share)
        #expect(abs(model.totalPercentage - 100) < 0.1) // last ingredient absorbs rounding
    }

    @Test func userEdited_Locks_OtherIngredientsRedistribute() {
        let model = RecipeFormViewModel()
        model.addIngredient(Ingredient(name: "A"))
        model.addIngredient(Ingredient(name: "B"))

        let id = model.ingredientDrafts[0].id
        model.userEdited(id: id, percentage: "60")

        #expect(model.ingredientDrafts[0].percentage == "60")
        #expect(model.ingredientDrafts[0].isLocked == true)
        #expect(model.ingredientDrafts[1].percentage == model.formatPercentage(40))
        #expect(model.ingredientDrafts[1].isLocked == false)
    }

    @Test func addIngredient_AfterLock_DistributesRemainingToUnlocked() {
        let model = RecipeFormViewModel()
        model.addIngredient(Ingredient(name: "A"))
        model.addIngredient(Ingredient(name: "B"))
        model.userEdited(id: model.ingredientDrafts[0].id, percentage: "60")

        model.addIngredient(Ingredient(name: "C"))

        #expect(model.ingredientDrafts[0].percentage == "60")
        #expect(model.ingredientDrafts[1].percentage == model.formatPercentage(20))
        #expect(model.ingredientDrafts[2].percentage == model.formatPercentage(20))
    }

    @Test func removeIngredient_Redistributes() {
        let model = RecipeFormViewModel()
        model.addIngredient(Ingredient(name: "A"))
        model.addIngredient(Ingredient(name: "B"))
        model.addIngredient(Ingredient(name: "C"))

        model.removeIngredient(at: IndexSet(integer: 2))

        #expect(model.ingredientDrafts[0].percentage == model.formatPercentage(50))
        #expect(model.ingredientDrafts[1].percentage == model.formatPercentage(50))
    }

    @Test func totalPercentage_SumsAllDrafts() {
        let model = RecipeFormViewModel()
        model.addIngredient(Ingredient(name: "A"))
        model.addIngredient(Ingredient(name: "B"))
        #expect(model.totalPercentage == 100)
    }

    @Test func totalPercentage_EmptyDrafts_ReturnsZero() {
        let model = RecipeFormViewModel()
        #expect(model.totalPercentage == 0)
    }

    @Test func addIngredient_WhenLockedSumExceeds100_GetsZero() {
        let model = RecipeFormViewModel()
        model.addIngredient(Ingredient(name: "A"))
        model.userEdited(id: model.ingredientDrafts[0].id, percentage: "100")

        model.addIngredient(Ingredient(name: "B"))

        #expect(model.ingredientDrafts[0].percentage == "100")
        #expect(model.ingredientDrafts[1].percentage == model.formatPercentage(0))
    }
}
