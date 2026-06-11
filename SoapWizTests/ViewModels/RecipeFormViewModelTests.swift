import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeFormViewModel", .serialized)
@MainActor
struct RecipeFormViewModelTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Recipe.self, RecipeIngredient.self, RecipeProduct.self, Ingredient.self, IngredientPurchase.self, IngredientCategory.self])
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
        model.oilDrafts[0].amount = 45

        let recipe = model.save(context: ctx)

        #expect(recipe.ingredients.count == 1)
        #expect(recipe.ingredients[0].percentage == 45)
        let allRI = try ctx.fetch(FetchDescriptor<RecipeIngredient>())
        #expect(allRI.count == 1)
    }

    // MARK: - Percentage distribution

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
        let ri = RecipeIngredient(ingredient: ingredient, percentage: 75)
        ri.recipe = recipe
        ctx.insert(ri)

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

        #expect(result.oils.isEmpty)
        #expect(result.additives.isEmpty)
        #expect(result.fragrances.isEmpty)
        #expect(result.lye.isEmpty)
        #expect(result.total == 0)
    }

    @Test func breakdownAndCost_ZeroSize_ReturnsEmpty() {
        let model = RecipeFormViewModel()
        model.totalOilWeight = 100
        model.addOil(Ingredient(name: "Olive Oil"))
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 0

        let result = model.breakdownAndCost(for: draft)

        #expect(result.oils.isEmpty)
        #expect(result.total == 0)
    }

    @Test func breakdownAndCost_NoBatches_AmountsComputedCostZero() {
        let model = RecipeFormViewModel()
        model.totalOilWeight = 100
        model.addOil(Ingredient(name: "Olive Oil"))
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 100

        let result = model.breakdownAndCost(for: draft)

        #expect(result.oils[0].ingredientAmount == 100)
        #expect(result.oils[0].cost == 0)
        #expect(result.total == 0)
    }

    @Test func breakdownAndCost_SingleBatch_ComputesCostCorrectly() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Coconut Oil")
        ctx.insert(ingredient)
        let purchase = IngredientPurchase.mock(quantity: 500, totalPrice: 10.0)
        purchase.ingredient = ingredient
        ctx.insert(purchase)

        let model = RecipeFormViewModel()
        model.totalOilWeight = 100
        model.addOil(ingredient)
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 100

        let result = model.breakdownAndCost(for: draft)

        // 100g product / 100g batch = full batch. Oil = 100g × €0.02/g = €2.00
        #expect(result.oils[0].ingredientAmount == 100)
        #expect(result.oils[0].cost == 2.0)
        #expect(result.total == 2.0)
    }

    @Test func breakdownAndCost_MultipleBatches_UsesWeightedAverageCost() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let purchase1 = IngredientPurchase.mock(quantity: 500, totalPrice: 10.0)
        purchase1.ingredient = ingredient
        ctx.insert(purchase1)
        let purchase2 = IngredientPurchase.mock(quantity: 250, totalPrice: 7.5)
        purchase2.ingredient = ingredient
        ctx.insert(purchase2)

        let model = RecipeFormViewModel()
        model.totalOilWeight = 100
        model.addOil(ingredient)
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 100

        let result = model.breakdownAndCost(for: draft)

        let expected = 100 * (17.5 / 750.0)
        #expect(abs(result.oils[0].cost - expected) < 0.0001)
        #expect(abs(result.total - expected) < 0.0001)
    }

    @Test func breakdownAndCost_MultipleIngredients_SumsTotalCorrectly() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ing1 = Ingredient(name: "Coconut Oil")
        ctx.insert(ing1)
        let b1 = IngredientPurchase.mock(quantity: 1000, totalPrice: 10.0)  // €0.01/g
        b1.ingredient = ing1
        ctx.insert(b1)

        let ing2 = Ingredient(name: "Shea Butter")
        ctx.insert(ing2)
        let b2 = IngredientPurchase.mock(quantity: 500, totalPrice: 20.0)   // €0.04/g
        b2.ingredient = ing2
        ctx.insert(b2)

        let model = RecipeFormViewModel()
        model.totalOilWeight = 200
        model.addOil(ing1)
        model.addOil(ing2) // each gets 50%
        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 200

        let result = model.breakdownAndCost(for: draft)

        #expect(result.oils.count == 2)
        #expect(abs(result.total - 5.0) < 0.0001)
    }

    @Test func breakdownAndCost_PartsOfBatch_DividesBatchCost() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Coconut Oil")
        ctx.insert(ingredient)
        let purchase = IngredientPurchase.mock(quantity: 500, totalPrice: 10.0)
        purchase.ingredient = ingredient
        ctx.insert(purchase)

        let model = RecipeFormViewModel()
        model.totalOilWeight = 1000
        model.addOil(ingredient)
        var draft = RecipeProductDraft(unitSymbol: ProductUnit.partsOfBatch.rawValue)
        draft.size = 10

        let result = model.breakdownAndCost(for: draft)

        // 1000g oils × €0.02/g = €20 batch cost. 1/10 = €2.
        #expect(abs(result.total - 2.0) < 0.0001)
    }

    @Test func breakdownAndCost_ExceedingBatchWeight_ClampsAtBatchTotal() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Coconut Oil")
        ctx.insert(ingredient)
        let purchase = IngredientPurchase.mock(quantity: 500, totalPrice: 10.0)
        purchase.ingredient = ingredient
        ctx.insert(purchase)

        let model = RecipeFormViewModel()
        model.totalOilWeight = 100
        model.addOil(ingredient)

        var draft = RecipeProductDraft(unitSymbol: "kg")
        draft.size = 5  // 5000g vs 100g batch

        let result = model.breakdownAndCost(for: draft)

        #expect(result.exceedsBatchWeight == true)
        #expect(abs(result.total - model.batchTotalCost) < 0.0001)
    }

    @Test func init_AddsDefaultProductOnePartOfBatch() {
        let model = RecipeFormViewModel()
        #expect(model.productDrafts.count == 1)
        #expect(model.productDrafts[0].size == 1)
        #expect(model.productDrafts[0].unitSymbol == ProductUnit.partsOfBatch.rawValue)
    }

    @Test func batchTotalCost_IncludesAllCategories() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        ctx.insert(oil)
        let oilPurchase = IngredientPurchase.mock(quantity: 1000, totalPrice: 10.0)
        oilPurchase.ingredient = oil
        ctx.insert(oilPurchase)
        let lye = Ingredient(name: "Sodium Hydroxide")
        ctx.insert(lye)
        let lyePurchase = IngredientPurchase.mock(quantity: 1000, totalPrice: 8.0)
        lyePurchase.ingredient = lye
        ctx.insert(lyePurchase)

        let model = RecipeFormViewModel()
        model.totalOilWeight = 1000
        model.lyePurity = 100
        model.superFat = 0
        model.addOil(oil)
        model.lyeIngredient = lye

        // Oils: 1000g × €0.01 = €10
        // Lye: 1000 × 0.2 × 1 / 1 = 200g × €0.008 = €1.60
        #expect(abs(model.batchTotalCost - 11.60) < 0.001)
    }

    @Test func resolveDefaultLyeIngredient_PicksSodiumHydroxide() {
        let lyeCategory = IngredientCategory(name: IngredientCategory.Name.lyes)
        let naoh = Ingredient(name: "Sodium Hydroxide (Lye)", category: lyeCategory, unit: "g")
        let other = Ingredient(name: "Other Lye", category: lyeCategory, unit: "g")

        let model = RecipeFormViewModel()
        model.resolveDefaultLyeIngredient(from: [other, naoh])

        #expect(model.lyeIngredient?.name == "Sodium Hydroxide (Lye)")
    }

    @Test func resolveDefaultLyeIngredient_DoesNotOverrideExisting() {
        let lyeCategory = IngredientCategory(name: IngredientCategory.Name.lyes)
        let naoh = Ingredient(name: "Sodium Hydroxide", category: lyeCategory, unit: "g")
        let custom = Ingredient(name: "Custom Lye", category: lyeCategory, unit: "g")

        let model = RecipeFormViewModel()
        model.lyeIngredient = custom
        model.resolveDefaultLyeIngredient(from: [naoh, custom])

        #expect(model.lyeIngredient === custom)
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

        model.updateFragrance(id: id, amount: 10)

        #expect(model.fragranceDrafts[0].amount == 10)
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
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 5, unit: "g")
        model.addFragrance(fragrance)
        model.updateFragrance(id: model.fragranceDrafts[0].id, amount: 10, unit: "ml")
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
        #expect(model.additiveDrafts[0].amount == 5)
        #expect(model.additiveDrafts[0].unit == "g")
    }

    // MARK: - Calculated amounts — edge cases

    @Test func oilAmountCalculations_ZeroPurity_ReturnsNil() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = 1000
        model.lyePurity = 0

        #expect(model.oilAmountCalculations == nil)
    }

    @Test func oilAmountCalculations_PurityAbove100_ReturnsNil() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = 1000
        model.lyePurity = 101

        #expect(model.oilAmountCalculations == nil)
    }

    @Test func breakdownAndCost_DirectWeightMode_UsesOilShareNotPercentage() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ing1 = Ingredient(name: "Coconut Oil")
        ctx.insert(ing1)
        let b1 = IngredientPurchase.mock(quantity: 1000, totalPrice: 10.0)  // €0.01/g
        b1.ingredient = ing1
        ctx.insert(b1)

        let ing2 = Ingredient(name: "Olive Oil")
        ctx.insert(ing2)
        let b2 = IngredientPurchase.mock(quantity: 500, totalPrice: 20.0)   // €0.04/g
        b2.ingredient = ing2
        ctx.insert(b2)

        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.addOil(ing1)
        model.oilDrafts[0].amount = 300  // 300g
        model.addOil(ing2)
        model.oilDrafts[1].amount = 100  // 100g — batch total 400g

        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 200

        let result = model.breakdownAndCost(for: draft)

        // 200g / 400g batch = 0.5 share
        // ing1: 300 × 0.5 = 150g × €0.01 = €1.50
        // ing2: 100 × 0.5 =  50g × €0.04 = €2.00
        #expect(abs(result.oils[0].ingredientAmount - 150) < 0.001)
        #expect(abs(result.oils[1].ingredientAmount - 50) < 0.001)
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
        model.totalOilWeight = 0
        model.addOil(Ingredient(name: "Coconut Oil"))
        #expect(model.oilAmountCalculations == nil)
    }

    @Test func oilAmountCalculations_PercentageMode_SingleOil_ComputesWeightAndLye() throws {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)   // gets 100%
        model.totalOilWeight = 1000
        model.oilWeightUnit = "g"
        model.lyePurity = 100
        model.superFat = 0

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
        model.totalOilWeight = 1000
        model.oilWeightUnit = "g"
        model.lyePurity = 99
        model.superFat = 5

        let calcs = model.oilAmountCalculations
        #expect(calcs != nil)
        #expect(calcs?[0].lye == 0)
    }

    @Test func oilAmountCalculations_PercentageMode_KgUnit_NoConversion() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = 1
        model.oilWeightUnit = "kg"
        model.lyePurity = 100
        model.superFat = 0

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
        model.oilDrafts[0].amount = 500
        model.lyePurity = 100
        model.superFat = 0

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
        // amount stays 0 — treated as zero
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
        model.oilDrafts[0].amount = 500
        model.addOil(oilB)
        model.oilDrafts[1].amount = 500
        model.lyePurity = 100
        model.superFat = 0

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
        model.oilDrafts[0].amount = 500
        model.lyePurity = 100
        model.superFat = 0
        model.waterParts = 2

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
        model.totalOilWeight = 1000
        model.oilWeightUnit = "g"
        model.lyePurity = 100
        model.superFat = 0
        // waterParts = 1.5 (default)

        let rows = model.calculatedAmountRows
        // 1 oil row + oils total + NaOH + Water + Batch total = 5
        #expect(rows?.count == 5)
    }

    @Test func calculatedAmountRows_BatchTotalIsSumOfAll() throws {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = 1000
        model.oilWeightUnit = "g"
        model.lyePurity = 100
        model.superFat = 0
        model.waterParts = 1.5

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
        #expect(model.fragranceDrafts[0].amount == 10)
        #expect(model.fragranceDrafts[0].unit == "ml")
    }

    // MARK: - Extra ingredient data

    private func makeModelWithOils(oils: Double = 1000, waterParts: Double = 1.5) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = oils
        model.oilWeightUnit = "g"
        model.lyePurity = 100
        model.superFat = 0
        model.waterParts = waterParts
        return model
    }

    @Test func extraIngredientData_NoOils_ReturnsNil() {
        let model = RecipeFormViewModel()
        #expect(model.extraIngredientData == nil)
    }

    @Test func extraIngredientData_IncompleteOilWeight_ReturnsNil() {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = 0

        #expect(model.extraIngredientData == nil)
    }

    @Test func extraIngredientData_SectionA_HasTwoRows() throws {
        let model = makeModelWithOils()
        let data = try #require(model.extraIngredientData)
        #expect(data.sectionA.count == 2)
    }

    @Test func extraIngredientData_SectionB_HasSevenRows() throws {
        let model = makeModelWithOils()
        let data = try #require(model.extraIngredientData)
        #expect(data.sectionB.count == 7)
    }

    @Test func extraIngredientData_SodiumLactate_ComputesThreePercentages() throws {
        let model = makeModelWithOils(oils: 1000)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionA[0]
        #expect(row.label == "Sodium Lactate (60%)")
        #expect(abs(row.val1 - 10) < 0.001)
        #expect(abs(row.val2 - 20) < 0.001)
        #expect(abs(row.val3 - 30) < 0.001)
        #expect(row.naohLyeSolution == nil)
    }

    @Test func extraIngredientData_CitricAcid_ComputesThreePercentages() throws {
        let model = makeModelWithOils(oils: 1000)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionA[1]
        #expect(row.label == "Citric Acid Powder")
        #expect(abs(row.val1 - 10) < 0.001)
        #expect(abs(row.val2 - 20) < 0.001)
        #expect(abs(row.val3 - 30) < 0.001)
    }

    @Test func extraIngredientData_CitricAcid_NaOHSubRow_DividedByLyeConcentration() throws {
        // waterParts = 1.5 → lyeConc = 1 / 2.5 = 0.4
        let model = makeModelWithOils(oils: 1000, waterParts: 1.5)
        let data = try #require(model.extraIngredientData)
        let naoh = try #require(data.sectionA[1].naohLyeSolution)
        // citric_1pct = 10, naoh_pure = 10 * 0.625 = 6.25, displayed = 6.25 / 0.4 = 15.625
        #expect(abs(naoh.v1 - 15.625) < 0.001)
        #expect(abs(naoh.v2 - 31.25) < 0.001)
        #expect(abs(naoh.v3 - 46.875) < 0.001)
    }

    @Test func extraIngredientData_CitricAcid_NaOHSubRow_ScalesWithLyeConcentration() throws {
        // waterParts = 1.0 → lyeConc = 0.5; same citric but higher displayed (less concentrated lye)
        let modelA = makeModelWithOils(oils: 1000, waterParts: 1.5) // lyeConc = 0.4
        let modelB = makeModelWithOils(oils: 1000, waterParts: 1.0) // lyeConc = 0.5
        let dataA = try #require(modelA.extraIngredientData)
        let dataB = try #require(modelB.extraIngredientData)
        let naohA = try #require(dataA.sectionA[1].naohLyeSolution)
        let naohB = try #require(dataB.sectionA[1].naohLyeSolution)
        // Higher concentration (0.5 > 0.4) → smaller displayed volume
        #expect(naohB.v1 < naohA.v1)
    }

    @Test func extraIngredientData_EOFO_ComputesCorrectly() throws {
        let model = makeModelWithOils(oils: 1000)
        // fragrancePercentage defaults to 3 → 1000 × 0.03 = 30
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[0]
        #expect(row.label == "EO / Fragrance Oil")
        #expect(abs(row.minValue - 30) < 0.001)
        #expect(row.maxValue == nil)
        #expect(row.naohLyeSolution == nil)
    }

    @Test func extraIngredientData_AscorbicAcid_ComputesValueAndNaOH() throws {
        // waterParts = 1.5 → lyeConc = 0.4
        let model = makeModelWithOils(oils: 1000, waterParts: 1.5)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[1]
        #expect(row.label == "Ascorbic Acid")
        #expect(abs(row.minValue - 10) < 0.001)
        #expect(row.maxValue == nil)
        // naoh = 10 * 0.2020 / 0.4 = 5.05
        let naoh = try #require(row.naohLyeSolution)
        #expect(abs(naoh - 5.05) < 0.001)
    }

    @Test func extraIngredientData_LacticAcid_ComputesValueAndNaOH() throws {
        // waterParts = 1.5 → lyeConc = 0.4
        let model = makeModelWithOils(oils: 1000, waterParts: 1.5)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[2]
        #expect(row.label == "Lactic Acid")
        #expect(abs(row.minValue - 7.5) < 0.001)
        #expect(row.maxValue == nil)
        // naoh = 7.5 * 0.5920 / 0.4 = 11.1
        let naoh = try #require(row.naohLyeSolution)
        #expect(abs(naoh - 11.1) < 0.001)
    }

    @Test func extraIngredientData_TetrasodiumEDTA_UsesBatchTotal() throws {
        // oils = 1000, lye = 200, water = 300 → batchTotal = 1500
        let model = makeModelWithOils(oils: 1000, waterParts: 1.5)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[3]
        #expect(row.label == "Tetrasodium EDTA")
        // 1500 * 0.005 = 7.5
        #expect(abs(row.minValue - 7.5) < 0.001)
        #expect(row.maxValue == nil)
        #expect(row.naohLyeSolution == nil)
    }

    @Test func extraIngredientData_SodiumCitrate_ComputesRange() throws {
        let model = makeModelWithOils(oils: 1000)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[4]
        #expect(row.label == "Sodium Citrate")
        #expect(abs(row.minValue - 13) < 0.001)
        let max = try #require(row.maxValue)
        #expect(abs(max - 39) < 0.001)
    }

    @Test func extraIngredientData_PotassiumCitrate_ComputesRange() throws {
        let model = makeModelWithOils(oils: 1000)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[5]
        #expect(row.label == "Potassium Citrate")
        #expect(abs(row.minValue - 16) < 0.001)
        let max = try #require(row.maxValue)
        #expect(abs(max - 48) < 0.001)
    }

    @Test func extraIngredientData_ROE_ComputesRange() throws {
        let model = makeModelWithOils(oils: 1000)
        let data = try #require(model.extraIngredientData)
        let row = data.sectionB[6]
        #expect(row.label == "Rosemary Oleoresin (ROE)")
        #expect(abs(row.minValue - 0.4) < 0.0001)
        let max = try #require(row.maxValue)
        #expect(abs(max - 0.5) < 0.0001)
    }

    @Test func extraIngredientData_ScalesWithOilWeight() throws {
        let model2000 = makeModelWithOils(oils: 2000)
        let model1000 = makeModelWithOils(oils: 1000)
        let data2000 = try #require(model2000.extraIngredientData)
        let data1000 = try #require(model1000.extraIngredientData)
        // All values should double when oil weight doubles
        #expect(abs(data2000.sectionA[0].val1 - data1000.sectionA[0].val1 * 2) < 0.001)
        #expect(abs(data2000.sectionB[0].minValue - data1000.sectionB[0].minValue * 2) < 0.001)
    }

    // MARK: - Default ingredient unit

    @Test func defaultFragranceUnit_PercentageMode_IsPercentageOfOils() {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        #expect(model.defaultFragranceUnit == "% of oils")
    }

    @Test func defaultFragranceUnit_AbsoluteMode_MatchesWeightUnit() {
        let model = RecipeFormViewModel()
        model.weightUnit = "oz"
        #expect(model.defaultFragranceUnit == "oz")
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
        model.weightUnit = "kg"
        model.addFragrance(Ingredient(name: "Lavender EO"))
        #expect(model.fragranceDrafts[0].unit == "kg")
    }

    // MARK: - Breakdown unit consistency (non-gram oil unit)

    @Test func wholeBatchBreakdown_KgOilUnit_ExpressesAllAmountsInOilUnit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil")
        ctx.insert(oil)
        let additive = Ingredient(name: "Sodium Lactate")
        ctx.insert(additive)

        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "kg"
        model.totalOilWeight = 1          // 1 kg of oils
        model.lyePurity = 100
        model.superFat = 0
        model.addOil(oil)                 // 100%
        model.addAdditive(additive)
        // additive entered in grams while oils are in kg
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 500, unit: "g")

        let breakdown = model.wholeBatchBreakdown

        // Oil amount stays in the oil unit (1 kg)
        #expect(abs(breakdown.oils[0].ingredientAmount - 1) < 1e-6)
        // 500 g additive expressed in the oil unit → 0.5 kg
        let additiveRow = try #require(breakdown.additives.first)
        #expect(abs(additiveRow.ingredientAmount - 0.5) < 1e-6)
    }

    @Test func wholeBatchBreakdown_KgOilUnit_CostUsesGramEquivalent() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let additive = Ingredient(name: "Sodium Lactate")
        ctx.insert(additive)
        let purchase = IngredientPurchase.mock(quantity: 1000, totalPrice: 10.0) // €0.01/g
        purchase.ingredient = additive
        ctx.insert(purchase)
        let oil = Ingredient(name: "Olive Oil")
        ctx.insert(oil)

        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "kg"
        model.totalOilWeight = 1
        model.addOil(oil)
        model.addAdditive(additive)
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 500, unit: "g")

        let additiveRow = try #require(model.wholeBatchBreakdown.additives.first)
        // 0.5 kg = 500 g × €0.01/g = €5.00 — cost is independent of the display unit
        #expect(abs(additiveRow.cost - 5.0) < 1e-6)
    }

    @Test func displayedAmount_MassUnitAdditive_ShowsEnteredUnit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil")
        ctx.insert(oil)
        let additive = Ingredient(name: "Titanium Dioxide")
        ctx.insert(additive)

        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.addOil(oil)
        model.addAdditive(additive)
        // Entered as 2 oz while the oil unit is grams.
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 2, unit: "oz")

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        let display = model.displayedAmount(for: row, usesEnteredUnit: true)
        #expect(display.unit == "oz")
        #expect(abs(display.amount - 2) < 1e-6)
    }

    @Test func displayedAmount_PercentageAdditive_ShowsOilWeightUnit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil")
        ctx.insert(oil)
        let additive = Ingredient(name: "Sodium Lactate")
        ctx.insert(additive)

        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "kg"
        model.totalOilWeight = 1
        model.addOil(oil)
        model.addAdditive(additive)
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 2, unit: "% of oils")

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        let display = model.displayedAmount(for: row, usesEnteredUnit: true)
        // 2% of 1 kg oils = 0.02 kg, shown in the oil weight unit
        #expect(display.unit == "kg")
        #expect(abs(display.amount - 0.02) < 1e-6)
    }

    @Test func displayedAmount_Oil_ShowsOilWeightUnit() throws {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.addOil(Ingredient(name: "Olive Oil"))

        let row = try #require(model.wholeBatchBreakdown.oils.first)
        let display = model.displayedAmount(for: row, usesEnteredUnit: false)
        #expect(display.unit == "g")
        #expect(abs(display.amount - 1000) < 1e-6)
    }

    @Test func displayedAmount_OilRow_IgnoresAdditiveUnitForSameIngredient() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let shared = Ingredient(name: "Coconut Oil")
        ctx.insert(shared)

        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.addOil(shared)        // 100% oil
        model.addAdditive(shared)   // same ingredient also added as an additive
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 2, unit: "oz")

        let oilRow = try #require(model.wholeBatchBreakdown.oils.first)
        let display = model.displayedAmount(for: oilRow, usesEnteredUnit: false)
        // Oil row stays in the oil weight unit, not the additive's "oz".
        #expect(display.unit == "g")
    }

    @Test func breakdownAndCost_FixedSize_KgOilUnit_SharesCorrectly() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil")
        ctx.insert(oil)

        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "kg"
        model.totalOilWeight = 1          // 1 kg = 1000 g batch (no lye/additives)
        model.lyePurity = 100
        model.superFat = 0
        model.addOil(oil)

        var draft = RecipeProductDraft(unitSymbol: "g")
        draft.size = 500                  // 500 g of a 1000 g batch → half

        let result = model.breakdownAndCost(for: draft)

        // Oil amount in the oil unit: 1 kg × 0.5 = 0.5 kg
        #expect(abs(result.oils[0].ingredientAmount - 0.5) < 1e-6)
    }

    // MARK: - Volume-unit ingredients (density conversion)

    /// Oils in grams plus one additive entered as a volume, with optional
    /// ingredient density and an optional purchase to give it a cost.
    private func makeModelWithVolumeAdditive(
        ctx: ModelContext,
        amount: Double,
        unit: String,
        density: Double?,
        purchase: IngredientPurchase? = nil
    ) -> RecipeFormViewModel {
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let additive = Ingredient(name: "Glycerin", unit: "ml")
        additive.density = density
        ctx.insert(additive)
        if let purchase {
            purchase.ingredient = additive
            ctx.insert(purchase)
        }

        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.addOil(oil)
        model.addAdditive(additive)
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: amount, unit: unit)
        return model
    }

    @Test func wholeBatchBreakdown_VolumeAdditive_CustomDensity_ConvertsToMass() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModelWithVolumeAdditive(ctx: ctx, amount: 100, unit: "ml", density: 1.26)

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        // 100 ml × 1.26 g/ml = 126 g in the batch (oils) unit
        #expect(abs(row.ingredientAmount - 126) < 1e-6)
    }

    @Test func wholeBatchBreakdown_VolumeAdditive_NoDensity_UsesDefaultDensity() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModelWithVolumeAdditive(ctx: ctx, amount: 1.2, unit: "L", density: nil)

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        // 1.2 L = 1200 ml × 0.92 g/ml (default) = 1104 g
        #expect(abs(row.ingredientAmount - 1104) < 1e-6)
    }

    @Test func wholeBatchBreakdown_VolumeAdditive_ComputesCostFromMassEquivalent() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = IngredientPurchase.mock(quantity: 1000, totalPrice: 10.0) // €0.01/unit
        let model = makeModelWithVolumeAdditive(ctx: ctx, amount: 100, unit: "ml", density: 1.26, purchase: purchase)

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        // 126 g equivalent × €0.01 = €1.26
        #expect(abs(row.cost - 1.26) < 1e-6)
    }

    @Test func wholeBatchBreakdown_VolumeAdditive_NonPositiveDensity_IsOmitted() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModelWithVolumeAdditive(ctx: ctx, amount: 100, unit: "ml", density: 0)

        #expect(model.wholeBatchBreakdown.additives.isEmpty)
    }

    @Test func displayedAmount_VolumeAdditive_ShowsEnteredVolumeWithCustomDensityNote() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModelWithVolumeAdditive(ctx: ctx, amount: 100, unit: "ml", density: 1.26)

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        let display = model.displayedAmount(for: row, usesEnteredUnit: true)

        #expect(display.unit == "ml")
        #expect(abs(display.amount - 100) < 1e-6)
        let mass = 126.0.formatted(.number.precision(.fractionLength(0...2)))
        let density = 1.26.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
        #expect(display.conversionNote == "≈ \(mass) g (density \(density) g/ml, custom)")
    }

    @Test func displayedAmount_VolumeAdditive_DefaultDensity_NoteSaysDefault() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModelWithVolumeAdditive(ctx: ctx, amount: 1.2, unit: "L", density: nil)

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        let display = model.displayedAmount(for: row, usesEnteredUnit: true)

        #expect(display.unit == "L")
        #expect(abs(display.amount - 1.2) < 1e-6)
        let note = try #require(display.conversionNote)
        #expect(note.contains("default"))
        #expect(note.contains("g/ml"))
    }

    @Test func displayedAmount_MassAdditive_HasNoConversionNote() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let additive = Ingredient(name: "Salt", unit: "g")
        ctx.insert(additive)

        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.addOil(oil)
        model.addAdditive(additive)
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 2, unit: "oz")

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        let display = model.displayedAmount(for: row, usesEnteredUnit: true)

        #expect(display.unit == "oz")
        #expect(display.conversionNote == nil)
    }

    @Test func displayedAmount_VolumeAdditive_ScaledProduct_ScalesEnteredVolume() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModelWithVolumeAdditive(ctx: ctx, amount: 100, unit: "ml", density: 1.26)
        var draft = RecipeProductDraft(unitSymbol: ProductUnit.partsOfBatch.rawValue)
        draft.size = 2

        let result = model.breakdownAndCost(for: draft)

        let row = try #require(result.additives.first)
        let display = model.displayedAmount(for: row, usesEnteredUnit: true)
        // Half the batch → half the entered volume, converted back through the same density.
        #expect(display.unit == "ml")
        #expect(abs(display.amount - 50) < 1e-6)
    }

    // MARK: - Fragrance target

    private func makeModelWithOilsAndFragrance(fragranceUnit: String) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.fragrancePercentage = 3
        model.addOil(Ingredient(name: "Olive Oil"))          // 100% → 1000 g oils
        model.addFragrance(Ingredient(name: "Lavender EO"))
        model.updateFragrance(id: model.fragranceDrafts[0].id, unit: fragranceUnit)
        return model
    }

    @Test func fragranceTarget_MassUnit_ShowsTargetTotalAndPercentage() throws {
        let model = makeModelWithOilsAndFragrance(fragranceUnit: "g")
        let target = try #require(model.fragranceTarget)
        #expect(target.percentage == 3)
        // 3% of 1000 g oils = 30 g
        #expect(target.text.contains("30"))
        #expect(target.text.contains("g"))
        #expect(target.text.contains("3%"))
    }

    @Test func fragranceTarget_OzUnit_ConvertsTargetToThatUnit() throws {
        let model = makeModelWithOilsAndFragrance(fragranceUnit: "oz")
        let target = try #require(model.fragranceTarget)
        #expect(target.text.contains("oz"))
        #expect(target.text.contains("3%"))
    }

    @Test func fragranceTarget_EnteredOverTarget_SetsFlag() throws {
        let model = makeModelWithOilsAndFragrance(fragranceUnit: "g")
        // Target is 3% of 1000 g = 30 g; enter 60 g.
        model.updateFragrance(id: model.fragranceDrafts[0].id, amount: 60)
        let target = try #require(model.fragranceTarget)
        #expect(target.isOverTarget == true)
    }

    @Test func fragranceTarget_EnteredUnderTarget_FlagFalse() throws {
        let model = makeModelWithOilsAndFragrance(fragranceUnit: "g")
        model.updateFragrance(id: model.fragranceDrafts[0].id, amount: 20)
        let target = try #require(model.fragranceTarget)
        #expect(target.isOverTarget == false)
    }

    @Test func fragranceTarget_PercentageUnit_ReturnsNil() {
        // Default unit in percentage mode is "% of oils".
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.totalOilWeight = 1000
        model.addOil(Ingredient(name: "Olive Oil"))
        model.addFragrance(Ingredient(name: "Lavender EO"))
        #expect(model.fragranceTarget == nil)
    }

    @Test func fragranceTarget_MixedUnits_ReturnsNil() {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.totalOilWeight = 1000
        model.addOil(Ingredient(name: "Olive Oil"))
        model.addFragrance(Ingredient(name: "A"))
        model.addFragrance(Ingredient(name: "B"))
        model.updateFragrance(id: model.fragranceDrafts[0].id, unit: "g")
        model.updateFragrance(id: model.fragranceDrafts[1].id, unit: "oz")
        #expect(model.fragranceTarget == nil)
    }

    @Test func fragranceTarget_NoFragrances_ReturnsNil() {
        let model = makeModelWithOils()
        #expect(model.fragranceTarget == nil)
    }

    @Test func fragranceTarget_NoOils_ReturnsNil() {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.addFragrance(Ingredient(name: "Lavender EO"))
        model.updateFragrance(id: model.fragranceDrafts[0].id, unit: "g")
        #expect(model.fragranceTarget == nil)
    }
}

// MARK: - Mocks

extension IngredientPurchase {
    static func mock(
        quantity: Double = 500,
        totalPrice: Double = 10.0
    ) -> IngredientPurchase {
        IngredientPurchase(
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
