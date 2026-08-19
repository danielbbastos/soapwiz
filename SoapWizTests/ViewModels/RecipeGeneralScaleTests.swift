import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The shared 100% scale a non-soap recipe puts its base rows and percentage
/// additives on, and the amounts that fall out of it.
@Suite("Non-soap percentage scale", .serialized)
@MainActor
struct RecipeGeneralScaleTests: RecipeFormTestHelpers {

    private func makeIngredient(
        _ ctx: ModelContext,
        name: String,
        unit: String = "g",
        category: String? = IngredientCategory.Name.additives,
        purchase: (quantity: Double, price: Double)? = nil
    ) -> Ingredient {
        let ingredient = Ingredient(name: name, unit: unit)
        if let category {
            let category = IngredientCategory(name: category)
            ctx.insert(category)
            ingredient.category = category
        }
        ctx.insert(ingredient)
        if let purchase {
            let record = IngredientPurchase.mock(quantity: purchase.quantity, totalPrice: purchase.price)
            record.ingredient = ingredient
            ctx.insert(record)
        }
        return ingredient
    }

    /// 1 000 g declared total, one base ingredient at 100%.
    private func makeGeneralModel(_ ctx: ModelContext) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.isNonSoapProduct = true
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.addOil(makeIngredient(ctx, name: "Apricot Kernel Oil", category: IngredientCategory.Name.oils))
        return model
    }

    // MARK: - One 100% scale

    @Test func percentageAdditive_TakesItsShareFromTheBaseRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        #expect(model.oilDrafts[0].amount == 100)

        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 1)

        #expect(model.oilDrafts[0].amount == 99)
        #expect(model.totalPercentage == 100)
    }

    @Test func removingThePercentageAdditive_ReturnsTheShareToTheBase() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 1)

        model.removeAdditive(at: IndexSet(integer: 0))

        #expect(model.oilDrafts[0].amount == 100)
        #expect(model.totalPercentage == 100)
    }

    @Test func countRow_DoesNotConsumeAnyOfThePercentageScale() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)

        model.addAdditive(makeIngredient(ctx, name: "Glass Jar", unit: RecipeUnitOptions.count))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 1)

        #expect(model.oilDrafts[0].amount == 100)
        #expect(model.totalPercentage == 100)
    }

    @Test func gramRow_DoesNotConsumeAnyOfThePercentageScale() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))

        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 10, unit: "g")

        #expect(model.oilDrafts[0].amount == 100)
        #expect(model.totalPercentage == 100)
    }

    /// A soap recipe keeps its additives on top of an oil total that is already
    /// 100% — the soap-making convention, and unchanged by this work.
    @Test func soapRecipe_PercentageAdditive_LeavesTheOilTotalAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.isNonSoapProduct = false
        model.addAdditive(makeIngredient(ctx, name: "Sodium Lactate"))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 1, unit: "% of oils")

        #expect(model.oilDrafts[0].amount == 100)
        #expect(model.totalPercentage == 100)
    }

    // MARK: - Resolved amounts

    @Test func percentOfTotal_ResolvesAgainstTheDeclaredTotal() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 1)

        let breakdown = model.wholeBatchBreakdown

        #expect(breakdown.oils[0].ingredientAmount == 990)
        #expect(breakdown.additives[0].ingredientAmount == 10)
        #expect(model.batchTotalWeight == 1000)
    }

    @Test func countRow_ContributesCostButNoWeight() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        let jar = makeIngredient(
            ctx, name: "Glass Jar", unit: RecipeUnitOptions.count, purchase: (quantity: 250, price: 500)
        )
        model.addAdditive(jar)
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 2)

        let breakdown = model.wholeBatchBreakdown
        let row = try #require(breakdown.additives.first)

        #expect(row.isCountBased)
        #expect(row.ingredientAmount == 2)
        // 500 for 250 jars → 2 each.
        #expect(abs(row.cost - 4) < 0.0001)
        #expect(model.batchTotalWeight == 1000)
    }

    @Test func countRow_IsDisplayedInItsOwnUnit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Glass Jar", unit: RecipeUnitOptions.count))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 3)

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        let display = model.displayedAmount(for: row, usesEnteredUnit: true)

        #expect(display.amount == 3)
        #expect(display.unit == RecipeUnitOptions.count)
        #expect(display.conversionNote == nil)
    }

    /// The regression this fixes: before "% of total" existed, a non-soap row in
    /// "% of batch" resolved to nil and vanished from the breakdown entirely.
    @Test func lyeBasedPercentageOnANonSoapRecipe_StillProducesNoRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 1, unit: "% of batch")

        #expect(model.wholeBatchBreakdown.additives.isEmpty)
    }

    @Test func countRow_ScaledToAProduct_KeepsItsCountUnit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(
            ctx, name: "Glass Jar", unit: RecipeUnitOptions.count, purchase: (quantity: 250, price: 500)
        ))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 1)

        var product = RecipeProductDraft(size: 1, unitSymbol: ProductUnit.partsOfBatch.rawValue)
        product.size = 1
        let scaled = model.breakdownAndCost(for: product)
        let row = try #require(scaled.additives.first)

        #expect(row.isCountBased)
        #expect(model.displayedAmount(for: row, usesEnteredUnit: true).unit == RecipeUnitOptions.count)
    }

    // MARK: - Rebalancing a saved recipe

    /// The regression: `load` locks every base row, and the old equal-share
    /// redistribution bailed out when nothing was unlocked — so a reopened
    /// recipe drifted past 100% with no correction.
    @Test func savedRecipe_AdditivePercentage_StillRebalancesTheBaseRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))
        let saved = model.save(context: ctx)

        let reloaded = RecipeFormViewModel()
        reloaded.load(from: saved)
        reloaded.updateAdditive(id: reloaded.additiveDrafts[0].id, amount: 5)

        #expect(reloaded.oilDrafts[0].amount == 95)
        #expect(reloaded.totalPercentage == 100)
    }

    /// Proportional, not equal-share: making room for an additive must not
    /// flatten the blend's ratios.
    @Test func rebalance_KeepsTheBaseRowsInProportion() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.isNonSoapProduct = true
        model.weightUnit = "%"
        model.totalOilWeight = 1000
        model.addOil(makeIngredient(ctx, name: "Apricot", category: IngredientCategory.Name.oils))
        model.addOil(makeIngredient(ctx, name: "Coconut", category: IngredientCategory.Name.oils))
        model.userEdited(id: model.oilDrafts[0].id, amount: 60)
        model.userEdited(id: model.oilDrafts[1].id, amount: 40)

        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 10)

        #expect(model.oilDrafts[0].amount == 54)
        #expect(model.oilDrafts[1].amount == 36)
        #expect(model.totalPercentage == 100)
    }

    @Test func rebalance_RemovingTheAdditive_ReturnsTheBaseRowsToFull() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 20)
        #expect(model.oilDrafts[0].amount == 80)

        model.removeAdditive(at: IndexSet(integer: 0))

        #expect(model.oilDrafts[0].amount == 100)
    }

    @Test func rebalance_AdditiveOverTheWholeScale_ClampsTheBaseRowsAtZero() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))

        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 140)

        #expect(model.oilDrafts[0].amount == 0)
    }

    @Test func rebalance_CountAndGramRows_LeaveTheBaseRowsAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Glass Jar", unit: RecipeUnitOptions.count))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 3)

        #expect(model.oilDrafts[0].amount == 100)
    }

    @Test func rebalance_SoapRecipe_IsUntouched() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.isNonSoapProduct = false
        model.addAdditive(makeIngredient(ctx, name: "Sodium Lactate"))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 5, unit: "% of oils")

        #expect(model.oilDrafts[0].amount == 100)
    }

    // MARK: - Calculated amounts

    /// The regression behind this: with additives sharing the 100% scale, a
    /// table built from the base rows alone reported 990 g for a 1 000 g batch.
    @Test func calculatedAmounts_IncludeThePercentageAdditive() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 1)

        let rows = try #require(model.calculatedAmountRows)
        let total = try #require(rows.last)

        #expect(rows.map(\.label) == ["Apricot Kernel Oil", "Activated Charcoal", "Batch total"])
        #expect(rows[0].weight == 990)
        #expect(rows[1].weight == 10)
        #expect(total.weight == 1000)
        #expect(total.isSummary)
    }

    @Test func calculatedAmounts_MatchTheBatchTotalWeight() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 2.5)

        let total = try #require(model.calculatedAmountRows?.last)

        #expect(abs(total.weight - model.batchTotalWeight) < 0.0001)
    }

    /// A count has no weight, so it has no place in a table of weights in one
    /// unit — it stays in the cost breakdown instead.
    @Test func calculatedAmounts_OmitCountRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Glass Jar", unit: RecipeUnitOptions.count))
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 1)

        let rows = try #require(model.calculatedAmountRows)

        #expect(!rows.contains { $0.label == "Glass Jar" })
        #expect(try #require(rows.last).weight == 1000)
    }

    @Test func calculatedAmounts_NoIngredients_IsNil() {
        let model = RecipeFormViewModel()
        model.isNonSoapProduct = true

        #expect(model.calculatedAmountRows == nil)
    }

    @Test func calculatedAmounts_NonSoap_NameNoLyeOrWater() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)

        let labels = try #require(model.calculatedAmountRows).map(\.label)

        #expect(labels.allSatisfy { !$0.contains("Water") && !$0.contains("NaOH") && !$0.contains("KOH") })
    }

    @Test func percentOfTotal_AbsoluteMode_ResolvesAgainstTheSummedBaseRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.isNonSoapProduct = true
        model.weightUnit = "g"
        let oil = makeIngredient(ctx, name: "Apricot Kernel Oil", category: IngredientCategory.Name.oils)
        model.addOil(oil)
        model.userEdited(id: model.oilDrafts[0].id, amount: 800)
        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))
        model.updateAdditive(
            id: model.additiveDrafts[0].id, amount: 10, unit: RecipeUnitOptions.percentOfTotal
        )

        let breakdown = model.wholeBatchBreakdown

        #expect(breakdown.additives[0].ingredientAmount == 80)
    }
}
