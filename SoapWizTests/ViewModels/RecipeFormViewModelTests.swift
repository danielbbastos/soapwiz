import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeFormViewModel", .serialized)
@MainActor
struct RecipeFormViewModelTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Recipe.self, RecipeIngredient.self, RecipeProduct.self, Ingredient.self, IngredientBatch.self, IngredientCategory.self])
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
        let ingredient = Ingredient(name: "Shea Butter", unit: "g")
        ctx.insert(ingredient)

        let model = RecipeFormViewModel()
        model.addIngredient(ingredient)
        model.addIngredient(ingredient)

        #expect(model.ingredientDrafts.count == 1)
    }

    @Test func saveInsertsRecipeIngredients() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Coconut Oil", unit: "g")
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
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
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

    @Test func removeIngredient_AllRemainingLocked_TotalsUnchanged() {
        let model = RecipeFormViewModel()
        model.addIngredient(Ingredient(name: "A"))
        model.addIngredient(Ingredient(name: "B"))
        model.addIngredient(Ingredient(name: "C"))
        model.userEdited(id: model.ingredientDrafts[0].id, percentage: "60")
        model.userEdited(id: model.ingredientDrafts[1].id, percentage: "40")

        model.removeIngredient(at: IndexSet(integer: 2))

        #expect(model.ingredientDrafts[0].percentage == "60")
        #expect(model.ingredientDrafts[1].percentage == "40")
        #expect(abs(model.totalPercentage - 100) < 0.1)
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

    // MARK: - Edit mode

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
        recipe.lyeParts = 1
        recipe.superFat = 8
        ctx.insert(recipe)

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.name == "Test Soap")
        #expect(model.desc == "A description")
        #expect(model.weightUnit == "oz")
        #expect(model.oilWeightUnit == "lb")
        #expect(model.lyeType == "NaOH")
        #expect(Double(model.lyePurity.replacingOccurrences(of: ",", with: ".")) == 95)
        #expect(Double(model.waterParts.replacingOccurrences(of: ",", with: ".")) == 3)
        #expect(Double(model.superFat.replacingOccurrences(of: ",", with: ".")) == 8)
        #expect(!model.totalOilWeight.isEmpty)
    }

    @Test func load_ZeroTotalOilWeight_LeavesFieldEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Test", desc: "")
        recipe.totalOilWeight = 0
        ctx.insert(recipe)

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.totalOilWeight.isEmpty)
    }

    @Test func load_PopulatesIngredientDrafts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(ingredient)
        let recipe = Recipe(name: "Test", desc: "")
        ctx.insert(recipe)
        let ri = RecipeIngredient(ingredient: ingredient, percentage: 75)
        ri.recipe = recipe
        ctx.insert(ri)

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.ingredientDrafts.count == 1)
        #expect(model.ingredientDrafts[0].ingredient.name == "Coconut Oil")
        #expect(Double(model.ingredientDrafts[0].percentage.replacingOccurrences(of: ",", with: ".")) == 75)
    }

    @Test func save_EditMode_UpdatesInPlace_RecipeCountStaysOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Original", desc: "")
        ctx.insert(recipe)

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.name = "Updated"
        model.lyePurity = "95"
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
        let ri = RecipeIngredient(ingredient: ing1, percentage: 100)
        ri.recipe = recipe
        ctx.insert(ri)

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.removeIngredient(at: IndexSet(integer: 0))
        model.addIngredient(ing2)
        model.save(context: ctx)

        let allRecipes = try ctx.fetch(FetchDescriptor<Recipe>())
        #expect(allRecipes.count == 1)
        let allRI = try ctx.fetch(FetchDescriptor<RecipeIngredient>())
        #expect(allRI.count == 1)
        #expect(allRI[0].ingredient.name == "Olive Oil")
    }

    // MARK: - Cost breakdown

    @Test func breakdownAndCost_NoIngredients_ReturnsEmptyAndZeroTotal() {
        let model = RecipeFormViewModel()
        let draft = RecipeProductDraft(unitSymbol: "g")

        let result = model.breakdownAndCost(for: draft)

        #expect(result.breakdown.isEmpty)
        #expect(result.total == 0)
    }

    @Test func breakdownAndCost_ZeroSize_AllAmountsZero() {
        let model = RecipeFormViewModel()
        model.addIngredient(Ingredient(name: "Olive Oil"))
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = "0"

        let result = model.breakdownAndCost(for: draft)

        #expect(result.breakdown[0].ingredientAmount == 0)
        #expect(result.breakdown[0].cost == 0)
        #expect(result.total == 0)
    }

    @Test func breakdownAndCost_NoBatches_AmountsComputedCostZero() {
        let model = RecipeFormViewModel()
        model.addIngredient(Ingredient(name: "Olive Oil"))
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = "100"

        let result = model.breakdownAndCost(for: draft)

        // 100% of 100g = 100g, but no batches → cost = 0
        #expect(result.breakdown[0].ingredientAmount == 100)
        #expect(result.breakdown[0].cost == 0)
        #expect(result.total == 0)
    }

    @Test func breakdownAndCost_SingleBatch_ComputesCostCorrectly() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Coconut Oil")
        ctx.insert(ingredient)
        let batch = IngredientBatch.mock(quantity: 500, totalPrice: 10.0)
        batch.ingredient = ingredient
        ctx.insert(batch)

        let model = RecipeFormViewModel()
        model.addIngredient(ingredient)
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = "100"

        let result = model.breakdownAndCost(for: draft)

        // 100% of 100g = 100g; cost/g = 10/500 = 0.02; total = 100 × 0.02 = 2.0
        #expect(result.breakdown[0].ingredientAmount == 100)
        #expect(result.breakdown[0].cost == 2.0)
        #expect(result.total == 2.0)
    }

    @Test func breakdownAndCost_MultipleBatches_UsesWeightedAverageCost() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let batch1 = IngredientBatch.mock(quantity: 500, totalPrice: 10.0)  // €0.020/g
        batch1.ingredient = ingredient
        ctx.insert(batch1)
        let batch2 = IngredientBatch.mock(quantity: 250, totalPrice: 7.5)   // €0.030/g
        batch2.ingredient = ingredient
        ctx.insert(batch2)

        let model = RecipeFormViewModel()
        model.addIngredient(ingredient)
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = "100"

        let result = model.breakdownAndCost(for: draft)

        // Weighted avg = (10 + 7.5) / (500 + 250) = 17.5/750 ≈ €0.02333/g
        let expected = 100 * (17.5 / 750.0)
        #expect(abs(result.breakdown[0].cost - expected) < 0.0001)
        #expect(abs(result.total - expected) < 0.0001)
    }

    @Test func breakdownAndCost_MultipleIngredients_SumsTotalCorrectly() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ing1 = Ingredient(name: "Coconut Oil")
        ctx.insert(ing1)
        let b1 = IngredientBatch.mock(quantity: 1000, totalPrice: 10.0)  // €0.01/g
        b1.ingredient = ing1
        ctx.insert(b1)

        let ing2 = Ingredient(name: "Shea Butter")
        ctx.insert(ing2)
        let b2 = IngredientBatch.mock(quantity: 500, totalPrice: 20.0)   // €0.04/g
        b2.ingredient = ing2
        ctx.insert(b2)

        let model = RecipeFormViewModel()
        model.addIngredient(ing1)
        model.addIngredient(ing2) // each gets 50%
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = "200"

        let result = model.breakdownAndCost(for: draft)

        // ing1: 50% of 200g = 100g × €0.01 = €1.00
        // ing2: 50% of 200g = 100g × €0.04 = €4.00
        #expect(result.breakdown.count == 2)
        #expect(abs(result.total - 5.0) < 0.0001)
    }

    @Test func breakdownAndCost_CommaDecimalSize_ParsesCorrectly() {
        let model = RecipeFormViewModel()
        model.addIngredient(Ingredient(name: "Olive Oil"))
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = "100,5"

        let result = model.breakdownAndCost(for: draft)

        // 100% of 100.5g = 100.5g
        #expect(result.breakdown[0].ingredientAmount == 100.5)
    }
}

// MARK: - Mocks

extension IngredientBatch {
    static func mock(
        quantity: Double = 500,
        totalPrice: Double = 10.0
    ) -> IngredientBatch {
        IngredientBatch(
            dateOfPurchase: Date(),
            quantity: quantity,
            totalPrice: totalPrice,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
    }
}
