import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeFormViewModel", .serialized)
@MainActor
struct RecipeFormViewModelTests: RecipeFormTestHelpers {

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
    @Test func addOilPreventsDuplicates() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Shea Butter", unit: "g")
        ctx.insert(ingredient)

        let model = RecipeFormViewModel()
        model.addOil(ingredient)
        model.addOil(ingredient)

        #expect(model.oilDrafts.count == 1)
    }
    @Test func applySeed_RoutesIngredientsToMatchingSections() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        let fragrances = IngredientCategory(name: IngredientCategory.Name.fragrances)
        let additives = IngredientCategory(name: IngredientCategory.Name.additives)
        let oil = Ingredient(name: "Olive Oil", category: oils, unit: "g")
        let fragrance = Ingredient(name: "Lavender EO", category: fragrances, unit: "g")
        let additive = Ingredient(name: "Kaolin Clay", category: additives, unit: "g")
        [oils, fragrances, additives].forEach { ctx.insert($0) }
        [oil, fragrance, additive].forEach { ctx.insert($0) }

        let model = RecipeFormViewModel()
        model.applySeed([oil, fragrance, additive])

        #expect(model.oilDrafts.map(\.ingredient.name) == ["Olive Oil"])
        #expect(model.fragranceDrafts.map(\.ingredient.name) == ["Lavender EO"])
        #expect(model.additiveDrafts.map(\.ingredient.name) == ["Kaolin Clay"])
    }
    @Test func applySeed_SkipsLyeAndUncategorised() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lyes = IngredientCategory(name: IngredientCategory.Name.lyes)
        let lye = Ingredient(name: "Sodium Hydroxide", category: lyes, unit: "g")
        let uncategorised = Ingredient(name: "Mystery", unit: "g")
        ctx.insert(lyes)
        [lye, uncategorised].forEach { ctx.insert($0) }

        let model = RecipeFormViewModel()
        model.applySeed([lye, uncategorised])

        #expect(model.oilDrafts.isEmpty)
        #expect(model.additiveDrafts.isEmpty)
        #expect(model.fragranceDrafts.isEmpty)
    }
    @Test func applySeed_RunsOnce() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        let oil = Ingredient(name: "Coconut Oil", category: oils, unit: "g")
        ctx.insert(oils)
        ctx.insert(oil)

        let model = RecipeFormViewModel()
        model.applySeed([oil])
        model.applySeed([oil])

        #expect(model.oilDrafts.count == 1)
    }
    @Test func saveInsertsRecipeIngredients() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(ingredient)

        let model = RecipeFormViewModel()
        model.name = "Test Recipe"
        model.addOil(ingredient)
        model.oilDrafts[0].amount = 45

        let recipe = model.save(context: ctx)

        #expect(recipe.ingredients.count == 1)
        #expect(recipe.ingredients[0].percentage == 45)
        let allRI = try ctx.fetch(FetchDescriptor<RecipeIngredient>())
        #expect(allRI.count == 1)
    }
    @Test func addOil_First_Gets100Percent() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "Coconut Oil"))
        #expect(model.oilDrafts[0].amount == 100)
    }
    @Test func addOil_Second_SplitsEqually() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "Coconut Oil"))
        model.addOil(Ingredient(name: "Olive Oil"))
        #expect(model.oilDrafts[0].amount == 50)
        #expect(model.oilDrafts[1].amount == 50)
    }
    @Test func addOil_Third_SplitsEqually() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "A"))
        model.addOil(Ingredient(name: "B"))
        model.addOil(Ingredient(name: "C"))
        // Share is rounded to 1 decimal: 100/3 → 33.3
        #expect(model.oilDrafts[0].amount == 33.3)
        #expect(model.oilDrafts[1].amount == 33.3)
        #expect(abs(model.totalPercentage - 100) < 0.1) // last ingredient absorbs rounding
    }
    @Test func userEdited_Locks_OtherIngredientsRedistribute() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "A"))
        model.addOil(Ingredient(name: "B"))

        let id = model.oilDrafts[0].id
        model.userEdited(id: id, amount: 60)

        #expect(model.oilDrafts[0].amount == 60)
        #expect(model.oilDrafts[0].isLocked == true)
        #expect(model.oilDrafts[1].amount == 40)
        #expect(model.oilDrafts[1].isLocked == false)
    }
    @Test func userEdited_DirectWeightMode_SetsAmountWithoutLockingOrRedistributing() {
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.addOil(Ingredient(name: "A"))
        model.addOil(Ingredient(name: "B"))
        model.oilDrafts[0].amount = 300
        model.oilDrafts[1].amount = 200

        model.userEdited(id: model.oilDrafts[0].id, amount: 400)

        #expect(model.oilDrafts[0].amount == 400)
        #expect(model.oilDrafts[0].isLocked == false)
        #expect(model.oilDrafts[1].amount == 200)
    }
    @Test func addOil_AfterLock_DistributesRemainingToUnlocked() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "A"))
        model.addOil(Ingredient(name: "B"))
        model.userEdited(id: model.oilDrafts[0].id, amount: 60)

        model.addOil(Ingredient(name: "C"))

        #expect(model.oilDrafts[0].amount == 60)
        #expect(model.oilDrafts[1].amount == 20)
        #expect(model.oilDrafts[2].amount == 20)
    }
    @Test func removeOil_Redistributes() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "A"))
        model.addOil(Ingredient(name: "B"))
        model.addOil(Ingredient(name: "C"))

        model.removeOil(at: IndexSet(integer: 2))

        #expect(model.oilDrafts[0].amount == 50)
        #expect(model.oilDrafts[1].amount == 50)
    }
    @Test func removeOil_AllRemainingLocked_TotalsUnchanged() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "A"))
        model.addOil(Ingredient(name: "B"))
        model.addOil(Ingredient(name: "C"))
        model.userEdited(id: model.oilDrafts[0].id, amount: 60)
        model.userEdited(id: model.oilDrafts[1].id, amount: 40)

        model.removeOil(at: IndexSet(integer: 2))

        #expect(model.oilDrafts[0].amount == 60)
        #expect(model.oilDrafts[1].amount == 40)
        #expect(abs(model.totalPercentage - 100) < 0.1)
    }
    @Test func totalPercentage_SumsAllDrafts() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "A"))
        model.addOil(Ingredient(name: "B"))
        #expect(model.totalPercentage == 100)
    }
    @Test func totalPercentage_EmptyDrafts_ReturnsZero() {
        let model = RecipeFormViewModel()
        #expect(model.totalPercentage == 0)
    }
    @Test func addOil_WhenLockedSumExceeds100_GetsZero() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "A"))
        model.userEdited(id: model.oilDrafts[0].id, amount: 100)

        model.addOil(Ingredient(name: "B"))

        #expect(model.oilDrafts[0].amount == 100)
        #expect(model.oilDrafts[1].amount == 0)
    }
    @Test func load_PopulatesAllConfigFields() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Test Soap", desc: "A description")
        recipe.weightUnit = "oz"
        recipe.totalOilWeight = 500
        recipe.oilWeightUnit = "lb"
        recipe.lyeType = "NaOH"
        recipe.lyePurity = 95
        recipe.waterParts = 3
        recipe.superFat = 8
        ctx.insert(recipe)

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.name == "Test Soap")
        #expect(model.desc == "A description")
        #expect(model.weightUnit == "oz")
        #expect(model.oilWeightUnit == "lb")
        #expect(model.lyeType == "NaOH")
        #expect(model.lyePurity == 95)
        #expect(model.waterParts == 3)
        #expect(model.superFat == 8)
        #expect(model.totalOilWeight > 0)
    }
    @Test func load_ZeroTotalOilWeight_LeavesFieldZero() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Test", desc: "")
        recipe.totalOilWeight = 0
        ctx.insert(recipe)

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.totalOilWeight == 0)
    }
    @Test func load_PopulatesIngredientDrafts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(ingredient)
        let recipe = Recipe(name: "Test", desc: "")
        ctx.insert(recipe)
        let recipeIngredient = RecipeIngredient(ingredient: ingredient, percentage: 75)
        recipeIngredient.recipe = recipe
        ctx.insert(recipeIngredient)

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.oilDrafts.count == 1)
        #expect(model.oilDrafts[0].ingredient.name == "Coconut Oil")
        #expect(model.oilDrafts[0].amount == 75)
    }
    @Test func save_EditMode_UpdatesInPlace_RecipeCountStaysOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Original", desc: "")
        ctx.insert(recipe)

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.name = "Updated"
        model.lyePurity = 95
        model.save(context: ctx)

        let all = try ctx.fetch(FetchDescriptor<Recipe>())
        #expect(all.count == 1)
        #expect(all[0].name == "Updated")
        #expect(all[0].lyePurity == 95)
    }
    @Test func save_EditMode_ReplacesOldIngredients() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ing1 = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(ing1)
        let ing2 = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ing2)
        let recipe = Recipe(name: "Test", desc: "")
        ctx.insert(recipe)
        let recipeIngredient = RecipeIngredient(ingredient: ing1, percentage: 100)
        recipeIngredient.recipe = recipe
        ctx.insert(recipeIngredient)

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.removeOil(at: IndexSet(integer: 0))
        model.addOil(ing2)
        model.save(context: ctx)

        let allRecipes = try ctx.fetch(FetchDescriptor<Recipe>())
        #expect(allRecipes.count == 1)
        let allRI = try ctx.fetch(FetchDescriptor<RecipeIngredient>())
        #expect(allRI.count == 1)
        #expect(allRI[0].ingredient.name == "Olive Oil")
    }
}
