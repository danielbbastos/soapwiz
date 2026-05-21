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

    @Test func saveInsertsRecipeIngredients() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(ingredient)

        let model = RecipeFormViewModel()
        model.name = "Test Recipe"
        model.addOil(ingredient)
        model.oilDrafts[0].amount = "45"

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
        model.addOil(ingredient)
        model.oilDrafts[0].amount = "33,5"

        let recipe = model.save(context: ctx)

        #expect(recipe.ingredients[0].percentage == 33.5)
    }

    // MARK: - Percentage distribution

    @Test func addOil_First_Gets100Percent() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "Coconut Oil"))
        #expect(model.oilDrafts[0].amount == model.formatPercentage(100))
    }

    @Test func addOil_Second_SplitsEqually() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "Coconut Oil"))
        model.addOil(Ingredient(name: "Olive Oil"))
        #expect(model.oilDrafts[0].amount == model.formatPercentage(50))
        #expect(model.oilDrafts[1].amount == model.formatPercentage(50))
    }

    @Test func addOil_Third_SplitsEqually() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "A"))
        model.addOil(Ingredient(name: "B"))
        model.addOil(Ingredient(name: "C"))
        let share = model.formatPercentage(100.0 / 3.0)
        #expect(model.oilDrafts[0].amount == share)
        #expect(model.oilDrafts[1].amount == share)
        #expect(abs(model.totalPercentage - 100) < 0.1) // last ingredient absorbs rounding
    }

    @Test func userEdited_Locks_OtherIngredientsRedistribute() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "A"))
        model.addOil(Ingredient(name: "B"))

        let id = model.oilDrafts[0].id
        model.userEdited(id: id, amount: "60")

        #expect(model.oilDrafts[0].amount == "60")
        #expect(model.oilDrafts[0].isLocked == true)
        #expect(model.oilDrafts[1].amount == model.formatPercentage(40))
        #expect(model.oilDrafts[1].isLocked == false)
    }

    @Test func userEdited_DirectWeightMode_SetsAmountWithoutLockingOrRedistributing() {
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.addOil(Ingredient(name: "A"))
        model.addOil(Ingredient(name: "B"))
        model.oilDrafts[0].amount = "300"
        model.oilDrafts[1].amount = "200"

        model.userEdited(id: model.oilDrafts[0].id, amount: "400")

        #expect(model.oilDrafts[0].amount == "400")
        #expect(model.oilDrafts[0].isLocked == false)
        #expect(model.oilDrafts[1].amount == "200")
    }

    @Test func addOil_AfterLock_DistributesRemainingToUnlocked() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "A"))
        model.addOil(Ingredient(name: "B"))
        model.userEdited(id: model.oilDrafts[0].id, amount: "60")

        model.addOil(Ingredient(name: "C"))

        #expect(model.oilDrafts[0].amount == "60")
        #expect(model.oilDrafts[1].amount == model.formatPercentage(20))
        #expect(model.oilDrafts[2].amount == model.formatPercentage(20))
    }

    @Test func removeOil_Redistributes() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "A"))
        model.addOil(Ingredient(name: "B"))
        model.addOil(Ingredient(name: "C"))

        model.removeOil(at: IndexSet(integer: 2))

        #expect(model.oilDrafts[0].amount == model.formatPercentage(50))
        #expect(model.oilDrafts[1].amount == model.formatPercentage(50))
    }

    @Test func removeOil_AllRemainingLocked_TotalsUnchanged() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "A"))
        model.addOil(Ingredient(name: "B"))
        model.addOil(Ingredient(name: "C"))
        model.userEdited(id: model.oilDrafts[0].id, amount: "60")
        model.userEdited(id: model.oilDrafts[1].id, amount: "40")

        model.removeOil(at: IndexSet(integer: 2))

        #expect(model.oilDrafts[0].amount == "60")
        #expect(model.oilDrafts[1].amount == "40")
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
        model.userEdited(id: model.oilDrafts[0].id, amount: "100")

        model.addOil(Ingredient(name: "B"))

        #expect(model.oilDrafts[0].amount == "100")
        #expect(model.oilDrafts[1].amount == model.formatPercentage(0))
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

        #expect(model.oilDrafts.count == 1)
        #expect(model.oilDrafts[0].ingredient.name == "Coconut Oil")
        #expect(Double(model.oilDrafts[0].amount.replacingOccurrences(of: ",", with: ".")) == 75)
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
        model.removeOil(at: IndexSet(integer: 0))
        model.addOil(ing2)
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
        model.addOil(Ingredient(name: "Olive Oil"))
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = "0"

        let result = model.breakdownAndCost(for: draft)

        #expect(result.breakdown[0].ingredientAmount == 0)
        #expect(result.breakdown[0].cost == 0)
        #expect(result.total == 0)
    }

    @Test func breakdownAndCost_NoBatches_AmountsComputedCostZero() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "Olive Oil"))
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
        model.addOil(ingredient)
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
        model.addOil(ingredient)
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
        model.addOil(ing1)
        model.addOil(ing2) // each gets 50%
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
        model.addOil(Ingredient(name: "Olive Oil"))
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = "100,5"

        let result = model.breakdownAndCost(for: draft)

        // 100% of 100.5g = 100.5g
        #expect(result.breakdown[0].ingredientAmount == 100.5)
    }

    // MARK: - Additives

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

        model.updateAdditive(id: id, amount: "5")

        #expect(model.additiveDrafts[0].amount == "5")
    }

    @Test func updateAdditive_Unit() {
        let model = RecipeFormViewModel()
        model.addAdditive(Ingredient(name: "Salt"))
        let id = model.additiveDrafts[0].id

        model.updateAdditive(id: id, unit: "ml")

        #expect(model.additiveDrafts[0].unit == "ml")
    }

    // MARK: - Fragrances

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

    @Test func updateFragrance_Amount() {
        let model = RecipeFormViewModel()
        model.addFragrance(Ingredient(name: "Lavender EO"))
        let id = model.fragranceDrafts[0].id

        model.updateFragrance(id: id, amount: "10")

        #expect(model.fragranceDrafts[0].amount == "10")
    }

    @Test func updateFragrance_Unit() {
        let model = RecipeFormViewModel()
        model.addFragrance(Ingredient(name: "Lavender EO"))
        let id = model.fragranceDrafts[0].id

        model.updateFragrance(id: id, unit: "g")

        #expect(model.fragranceDrafts[0].unit == "g")
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
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: "5", unit: "g")
        model.addFragrance(fragrance)
        model.updateFragrance(id: model.fragranceDrafts[0].id, amount: "10", unit: "ml")
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
        let ri = RecipeIngredient(ingredient: ingredient, percentage: 0, role: .additive)
        ri.additiveAmount = 5
        ri.additiveUnit = "g"
        ri.recipe = recipe
        ctx.insert(ri)

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.additiveDrafts.count == 1)
        #expect(model.additiveDrafts[0].ingredient.name == "Salt")
        #expect(Double(model.additiveDrafts[0].amount.replacingOccurrences(of: ",", with: ".")) == 5)
        #expect(model.additiveDrafts[0].unit == "g")
    }

    // MARK: - Calculated amounts — edge cases

    @Test func oilAmountCalculations_ZeroPurity_ReturnsNil() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = "1000"
        model.lyePurity = "0"

        #expect(model.oilAmountCalculations == nil)
    }

    @Test func oilAmountCalculations_PurityAbove100_ReturnsNil() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = "1000"
        model.lyePurity = "101"

        #expect(model.oilAmountCalculations == nil)
    }

    @Test func breakdownAndCost_DirectWeightMode_UsesOilShareNotPercentage() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ing1 = Ingredient(name: "Coconut Oil")
        ctx.insert(ing1)
        let b1 = IngredientBatch.mock(quantity: 1000, totalPrice: 10.0)  // €0.01/g
        b1.ingredient = ing1
        ctx.insert(b1)

        let ing2 = Ingredient(name: "Olive Oil")
        ctx.insert(ing2)
        let b2 = IngredientBatch.mock(quantity: 500, totalPrice: 20.0)   // €0.04/g
        b2.ingredient = ing2
        ctx.insert(b2)

        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.addOil(ing1)
        model.oilDrafts[0].amount = "300"  // 300g → 75% of 400g total
        model.addOil(ing2)
        model.oilDrafts[1].amount = "100"  // 100g → 25% of 400g total

        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = "200"

        let result = model.breakdownAndCost(for: draft)

        // ing1: 75% of 200g = 150g × €0.01 = €1.50
        // ing2: 25% of 200g = 50g × €0.04 = €2.00
        #expect(abs(result.breakdown[0].ingredientAmount - 150) < 0.001)
        #expect(abs(result.breakdown[1].ingredientAmount - 50) < 0.001)
        #expect(abs(result.total - 3.5) < 0.001)
    }

    // MARK: - Display weight unit

    @Test func displayWeightUnit_PercentageMode_UsesOilWeightUnit() {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "kg"
        #expect(model.displayWeightUnit == "kg")
    }

    @Test func displayWeightUnit_DirectWeightMode_UsesWeightUnit() {
        let model = RecipeFormViewModel()
        model.weightUnit = "oz"
        #expect(model.displayWeightUnit == "oz")
    }

    @Test func oilAmountCalculations_NoOils_ReturnsNil() {
        let model = RecipeFormViewModel()
        #expect(model.oilAmountCalculations == nil)
    }

    @Test func oilAmountCalculations_PercentageMode_ZeroTotalWeight_ReturnsNil() {
        let model = RecipeFormViewModel()
        // weightUnit defaults to "%"
        model.totalOilWeight = ""
        model.addOil(Ingredient(name: "Coconut Oil"))
        #expect(model.oilAmountCalculations == nil)
    }

    @Test func oilAmountCalculations_PercentageMode_SingleOil_ComputesWeightAndLye() throws {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)   // gets 100%
        model.totalOilWeight = "1000"
        model.oilWeightUnit = "g"
        model.lyePurity = "100"
        model.superFat = "0"

        let calcs = try #require(model.oilAmountCalculations)
        #expect(calcs.count == 1)
        #expect(calcs[0].weight == 1000)
        // lye = 1000 * 0.2 * (1 - 0/100) / (100/100) = 200
        #expect(abs(calcs[0].lye - 200) < 0.001)
    }

    @Test func oilAmountCalculations_PercentageMode_NoSapValue_LyeIsZero() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Unknown Oil")
        oil.sapValue = nil
        model.addOil(oil)
        model.totalOilWeight = "1000"
        model.oilWeightUnit = "g"
        model.lyePurity = "99"
        model.superFat = "5"

        let calcs = model.oilAmountCalculations
        #expect(calcs != nil)
        #expect(calcs?[0].lye == 0)
    }

    @Test func oilAmountCalculations_PercentageMode_KgUnit_NoConversion() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = "1"
        model.oilWeightUnit = "kg"
        model.lyePurity = "100"
        model.superFat = "0"

        let calcs = model.oilAmountCalculations
        // unit is just a label — value stays as 1 (kg)
        #expect(abs((calcs?[0].weight ?? -1) - 1.0) < 0.001)
    }

    @Test func oilAmountCalculations_DirectWeightMode_ComputesWeightAndLye() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.weightUnit = "g"
        model.addOil(oil)
        model.oilDrafts[0].amount = "500"
        model.lyePurity = "100"
        model.superFat = "0"

        let calcs = model.oilAmountCalculations
        #expect(calcs?.count == 1)
        #expect(abs((calcs?[0].weight ?? -1) - 500) < 0.001)
        // lye = 500 * 0.2 * 1 / 1 = 100
        #expect(abs((calcs?[0].lye ?? -1) - 100) < 0.001)
    }

    @Test func oilAmountCalculations_DirectWeightMode_ZeroAmount_ReturnsNil() {
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.addOil(Ingredient(name: "Coconut Oil"))
        // amount stays "" — treated as 0
        #expect(model.oilAmountCalculations == nil)
    }

    @Test func calculatedLyeAmount_SumsLyeFromAllOils() {
        let model = RecipeFormViewModel()
        let oilA = Ingredient(name: "A")
        oilA.sapValue = 0.2
        let oilB = Ingredient(name: "B")
        oilB.sapValue = 0.1
        model.weightUnit = "g"
        model.addOil(oilA)
        model.oilDrafts[0].amount = "500"
        model.addOil(oilB)
        model.oilDrafts[1].amount = "500"
        model.lyePurity = "100"
        model.superFat = "0"

        // lye_A = 500 * 0.2 = 100, lye_B = 500 * 0.1 = 50 → total = 150
        let lye = model.calculatedLyeAmount
        #expect(abs((lye ?? -1) - 150) < 0.001)
    }

    @Test func calculatedLyeAmount_NilWhenNoCalculations() {
        let model = RecipeFormViewModel()
        #expect(model.calculatedLyeAmount == nil)
    }

    @Test func calculatedWaterAmount_CorrectRatio() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.weightUnit = "g"
        model.addOil(oil)
        model.oilDrafts[0].amount = "500"
        model.lyePurity = "100"
        model.superFat = "0"
        model.waterParts = "2"

        // lye = 100, water = 100 * 2 = 200
        let water = model.calculatedWaterAmount
        #expect(abs((water ?? -1) - 200) < 0.001)
    }

    @Test func calculatedWaterAmount_NilWhenNoCalculations() {
        let model = RecipeFormViewModel()
        #expect(model.calculatedWaterAmount == nil)
    }

    @Test func calculatedAmountRows_NilWhenNoOils() {
        let model = RecipeFormViewModel()
        #expect(model.calculatedAmountRows == nil)
    }

    @Test func calculatedAmountRows_SingleOil_ReturnsFiveRows() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = "1000"
        model.oilWeightUnit = "g"
        model.lyePurity = "100"
        model.superFat = "0"
        // waterParts = "1.5" (default), lye ratio is always 1

        let rows = model.calculatedAmountRows
        // 1 oil row + oils total + NaOH + Water + Batch total = 5
        #expect(rows?.count == 5)
    }

    @Test func calculatedAmountRows_BatchTotalIsSumOfAll() throws {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = "1000"
        model.oilWeightUnit = "g"
        model.lyePurity = "100"
        model.superFat = "0"
        model.waterParts = "1.5"

        let rows = try #require(model.calculatedAmountRows)
        // oil=1000, lye=200, water=300 → batch=1500
        let batchRow = try #require(rows.last)
        #expect(batchRow.isSummary == true)
        #expect(abs(batchRow.weight - 1500) < 0.1)
        #expect(abs(batchRow.pct - 100) < 0.001)
    }

    @Test func load_PopulatesFragranceDrafts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Lavender EO", unit: "ml")
        ctx.insert(ingredient)
        let recipe = Recipe(name: "Test", desc: "")
        ctx.insert(recipe)
        let ri = RecipeIngredient(ingredient: ingredient, percentage: 0, role: .fragrance)
        ri.additiveAmount = 10
        ri.additiveUnit = "ml"
        ri.recipe = recipe
        ctx.insert(ri)

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.fragranceDrafts.count == 1)
        #expect(model.fragranceDrafts[0].ingredient.name == "Lavender EO")
        #expect(Double(model.fragranceDrafts[0].amount.replacingOccurrences(of: ",", with: ".")) == 10)
        #expect(model.fragranceDrafts[0].unit == "ml")
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
