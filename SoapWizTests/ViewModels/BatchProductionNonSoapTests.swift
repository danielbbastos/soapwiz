import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Batch production for a general (non-soap) recipe: it consumes what it lists
/// and nothing else. The lye and the water a soap batch carries are absent
/// rather than present at zero, even with lye sitting in the inventory and
/// resolved onto the recipe.
@Suite("Batch production – non-soap recipes", .serialized)
@MainActor
struct BatchProductionNonSoapTests: BatchProductionTestHelpers {

    private struct Seeded {
        let recipe: Recipe
        let oil: Ingredient
        let lye: Ingredient
    }

    /// 1 000 g of one oil as a general recipe, with sodium hydroxide stocked and
    /// available as a lye candidate. A soap recipe on this seed would draw lye
    /// and water; a general one must draw neither.
    private func seed(_ ctx: ModelContext, kind: RecipeKind = .general) -> Seeded {
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        let lyes = IngredientCategory(name: IngredientCategory.Name.lyes)
        ctx.insert(oils)
        ctx.insert(lyes)

        let oil = Ingredient(name: "Coconut Oil", category: oils, unit: "g")
        oil.sapValue = 0.2
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 5000, totalPrice: 50, daysAgo: 10)

        let lye = Ingredient(name: "Sodium Hydroxide", category: lyes, unit: "g")
        ctx.insert(lye)
        purchase(ctx, for: lye, quantity: 2000, totalPrice: 40, daysAgo: 10)

        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)
        recipe.name = "Massage Bar"
        recipe.recipeKind = kind.rawValue
        return Seeded(recipe: recipe, oil: oil, lye: lye)
    }

    // MARK: - Lye and water are absent, not zero

    @Test func requirements_GeneralRecipeWithLyeInStock_AsksForNoLye() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx)

        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [seeded.lye])

        #expect(model.requirements.map(\.ingredient.name) == ["Coconut Oil"])
    }

    @Test func create_GeneralRecipe_WritesNoLyeOrWaterLineItem() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx)
        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [seeded.lye])

        let batch = try #require(model.create(context: ctx))

        // The oil alone: no lye row, and no water row either — water has no
        // `Ingredient` to be drawn from, so a zero-weight line item would be the
        // only way it could appear.
        #expect(batch.lineItems.map(\.ingredientName) == ["Coconut Oil"])
        #expect(seeded.lye.totalRemaining == 2000)
    }

    /// The mirror of the test above: the kind gate must not reach into soap
    /// recipes, which still consume the lye they resolve.
    @Test func create_SoapRecipeOnTheSameSeed_StillWritesTheLyeLineItem() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx, kind: .soap)
        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [seeded.lye])

        let batch = try #require(model.create(context: ctx))

        #expect(batch.lineItems.contains { $0.ingredientName == "Sodium Hydroxide" })
        // 1 000 g oils × sap 0.2 at 100% purity and 0% super fat.
        #expect(abs(seeded.lye.totalRemaining - 1800) < 1e-6)
    }

    // MARK: - FIFO deduction

    @Test func create_GeneralRecipe_DeductsEveryIngredientOldestFirst() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        ctx.insert(oils)
        let oil = Ingredient(name: "Soy Wax", category: oils, unit: "g")
        ctx.insert(oil)
        let older = purchase(ctx, for: oil, quantity: 600, totalPrice: 6, daysAgo: 10, badge: "OLD")
        let newer = purchase(ctx, for: oil, quantity: 600, totalPrice: 12, daysAgo: 2, badge: "NEW")

        let fragrance = Ingredient(name: "Vanilla FO", unit: "g")
        ctx.insert(fragrance)
        purchase(ctx, for: fragrance, quantity: 100, totalPrice: 20, daysAgo: 5)

        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)
        recipe.recipeKind = RecipeKind.general.rawValue
        recipe.fragranceUnit = FragranceUnit.grams.rawValue
        let fragranceLine = RecipeIngredient(ingredient: fragrance, percentage: 0, role: .fragrance)
        fragranceLine.additiveAmount = 30
        fragranceLine.additiveUnit = "g"
        fragranceLine.recipe = recipe
        ctx.insert(fragranceLine)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        let batch = try #require(model.create(context: ctx))

        #expect(abs(older.remainingAmount - 0) < 1e-6)
        #expect(abs(newer.remainingAmount - 200) < 1e-6)
        #expect(abs(fragrance.totalRemaining - 70) < 1e-6)

        let waxItem = try #require(batch.lineItems.first { $0.ingredientName == "Soy Wax" })
        #expect(waxItem.draws.map(\.purchaseBadge) == ["OLD", "NEW"])
        #expect(batch.lineItems.count == 2)
    }

    /// A recipe stored with a lye-based fragrance unit and since switched to
    /// non-soap. The unit resolves against lye and water, so before `load`
    /// reconciled it the row dropped out of the breakdown entirely: the recipe
    /// listed a fragrance the batch never consumed.
    @Test func create_GeneralRecipeStoredWithALyeBasedFragranceUnit_StillDeductsIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx)
        let fragrance = Ingredient(name: "Vanilla FO", unit: "g")
        ctx.insert(fragrance)
        purchase(ctx, for: fragrance, quantity: 500, totalPrice: 100, daysAgo: 5)

        seeded.recipe.fragranceUnit = FragranceUnit.percentOfBatch.rawValue
        let fragranceLine = RecipeIngredient(ingredient: fragrance, percentage: 0, role: .fragrance)
        fragranceLine.additiveAmount = 3
        fragranceLine.additiveUnit = FragranceUnit.percentOfBatch.rawValue
        fragranceLine.recipe = seeded.recipe
        ctx.insert(fragranceLine)

        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [seeded.lye])
        let batch = try #require(model.create(context: ctx))

        // Reconciled to "% of oils": 3% of the 1 000 g base.
        let item = try #require(batch.lineItems.first { $0.ingredientName == "Vanilla FO" })
        #expect(abs(item.amountConsumed - 30) < 1e-6)
        #expect(abs(fragrance.totalRemaining - 470) < 1e-6)
    }

    // MARK: - Cost

    @Test func estimatedCost_GeneralRecipe_MatchesTheRecipesComputedCost() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx)

        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [seeded.lye])

        // One purchase per ingredient, so the recipe's purchase-weighted cost
        // and the batch's FIFO draw price are the same number.
        let engine = RecipeFormViewModel()
        engine.load(from: seeded.recipe)
        engine.resolveDefaultLyeIngredient(from: [seeded.lye])

        #expect(abs(model.estimatedCost - engine.batchTotalCost) < 1e-6)
        // 1 000 g of a 5 000 g / €50 purchase.
        #expect(abs(model.estimatedCost - 10) < 1e-6)
    }

    @Test func create_GeneralRecipe_SnapshotCostMatchesTheEstimate() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx)
        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [seeded.lye])
        model.batchCount = 3
        let estimated = model.estimatedCost

        let batch = try #require(model.create(context: ctx))

        #expect(abs(batch.totalCost - estimated) < 1e-6)
        #expect(abs(batch.totalCost - 30) < 1e-6)
    }

    // MARK: - Shortages

    @Test func shortages_GeneralRecipeWithoutEnoughStock_Fires() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx)
        for purchase in seeded.oil.purchases { purchase.remainingAmount = 400 }

        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [seeded.lye])

        #expect(model.shortages.map(\.ingredient.name) == ["Coconut Oil"])
        #expect(abs(try #require(model.shortages.first).shortfall - 600) < 1e-6)
        #expect(!model.canCreate)
    }

    /// The lye it never needed can be out of stock entirely without blocking a
    /// general recipe's batch.
    @Test func shortages_GeneralRecipeWithNoLyeInStock_DoesNotFire() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx)
        for purchase in seeded.lye.purchases { purchase.remainingAmount = 0 }

        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [seeded.lye])

        #expect(model.shortages.isEmpty)
        #expect(model.canCreate)
    }

    // MARK: - Batch weight

    /// A general recipe's total is its declared weight — base rows and the
    /// percentage additives share one 100% scale — plus the fragrances on top.
    @Test func totalBatchWeight_GeneralRecipe_IsBasePlusAdditivesPlusFragrances() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        ctx.insert(oils)
        let wax = Ingredient(name: "Soy Wax", category: oils, unit: "g")
        ctx.insert(wax)
        let butter = Ingredient(name: "Shea Butter", unit: "g")
        ctx.insert(butter)
        let fragrance = Ingredient(name: "Vanilla FO", unit: "g")
        ctx.insert(fragrance)

        // 90% wax + 10% shea of a declared 1 000 g, plus 30 g of fragrance.
        let recipe = Recipe(name: "Candle")
        recipe.recipeKind = RecipeKind.general.rawValue
        recipe.weightUnit = "%"
        recipe.oilWeightUnit = "g"
        recipe.totalOilWeight = 1000
        recipe.fragranceUnit = FragranceUnit.grams.rawValue
        ctx.insert(recipe)

        let waxLine = RecipeIngredient(ingredient: wax, percentage: 90, role: .oil)
        waxLine.recipe = recipe
        ctx.insert(waxLine)
        let butterLine = RecipeIngredient(ingredient: butter, percentage: 0, role: .additive)
        butterLine.additiveAmount = 10
        butterLine.additiveUnit = RecipeUnitOptions.percentOfTotal
        butterLine.recipe = recipe
        ctx.insert(butterLine)
        let fragranceLine = RecipeIngredient(ingredient: fragrance, percentage: 0, role: .fragrance)
        fragranceLine.additiveAmount = 30
        fragranceLine.additiveUnit = "g"
        fragranceLine.recipe = recipe
        ctx.insert(fragranceLine)

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])

        #expect(abs(model.totalBatchWeight - 1030) < 1e-6)
        #expect(model.batchWeightUnit == "g")
    }

    // MARK: - History

    @Test func batchSnapshot_GeneralRecipeDeleted_KeepsNameAndLineItems() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx)
        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [seeded.lye])
        let batch = try #require(model.create(context: ctx))

        ctx.delete(seeded.recipe)
        try ctx.save()

        // Nothing in the batch UI consults the recipe's kind, so a batch whose
        // recipe is gone renders from the snapshot alone.
        #expect(batch.recipe == nil)
        #expect(batch.recipeName == "Massage Bar")
        #expect(batch.lineItems.map(\.ingredientName) == ["Coconut Oil"])
        #expect(abs(batch.totalCost - 10) < 1e-6)
    }
}
