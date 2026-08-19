import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Batch production for a non-soap recipe that lists a countable component —
/// a jar, a wick, a label. It has to be deducted by the piece, priced by the
/// piece, and stay out of the batch's weight.
@Suite("Batch production – countable components", .serialized)
@MainActor
struct BatchProductionCountUnitTests: BatchProductionTestHelpers {

    /// 1 000 g of one oil plus one jar, as a non-soap recipe measured in grams.
    private func seed(_ ctx: ModelContext) -> (recipe: Recipe, oil: Ingredient, jar: Ingredient) {
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        let packages = IngredientCategory(name: "Packages")
        ctx.insert(oils)
        ctx.insert(packages)

        let oil = Ingredient(name: "Apricot Kernel Oil", category: oils, unit: "g")
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 5000, totalPrice: 50, daysAgo: 10)

        let jar = Ingredient(name: "Glass Jar 100ml", category: packages, unit: RecipeUnitOptions.count)
        ctx.insert(jar)
        purchase(ctx, for: jar, quantity: 250, totalPrice: 500, daysAgo: 10)

        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)
        recipe.recipeKind = RecipeKind.general.rawValue
        let jarLine = RecipeIngredient(ingredient: jar, percentage: 0, role: .additive)
        jarLine.additiveAmount = 2
        jarLine.additiveUnit = RecipeUnitOptions.count
        jarLine.recipe = recipe
        ctx.insert(jarLine)
        return (recipe, oil, jar)
    }

    @Test func requirements_CountRow_IsRequestedByThePiece() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx)

        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [])
        let jarRequirement = try #require(model.requirements.first { $0.ingredient.name == "Glass Jar 100ml" })

        #expect(jarRequirement.required == 2)
        #expect(jarRequirement.unit == RecipeUnitOptions.count)
        #expect(jarRequirement.available == 250)
        #expect(!jarRequirement.isShort)
    }

    @Test func totalBatchWeight_ExcludesTheCountRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx)

        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [])

        #expect(model.totalBatchWeight == 1000)
    }

    @Test func createBatch_DeductsTheCountFromStock() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx)
        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [])

        model.create(context: ctx)

        #expect(seeded.jar.totalRemaining == 248)
        #expect(seeded.oil.totalRemaining == 4000)
    }

    @Test func createBatch_PricesTheCountByThePiece() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx)
        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [])

        model.create(context: ctx)

        let batch = try #require(try ctx.fetch(FetchDescriptor<Batch>()).first)
        let jarItem = try #require(batch.lineItems.first { $0.ingredientName == "Glass Jar 100ml" })

        // 500 for 250 jars → 2 each, two jars → 4.
        #expect(abs(jarItem.cost - 4) < 0.0001)
        #expect(jarItem.amountConsumed == 2)
        #expect(jarItem.unit == RecipeUnitOptions.count)
    }

    @Test func shortage_FiresWhenThereAreNotEnoughPieces() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = seed(ctx)
        for purchase in seeded.jar.purchases { purchase.remainingAmount = 1 }

        let model = BatchProductionViewModel(recipe: seeded.recipe, lyeCandidates: [])

        #expect(model.shortages.contains { $0.ingredient.name == "Glass Jar 100ml" })
        #expect(!model.canCreate)
    }
}
