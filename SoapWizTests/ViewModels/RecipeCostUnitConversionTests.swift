import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeForm – cost unit conversion", .serialized)
@MainActor
struct RecipeCostUnitConversionTests: RecipeFormTestHelpers {

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
    @Test func wholeBatchBreakdown_VolumeAdditive_PricesPerInventoryVolume() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = IngredientPurchase.mock(quantity: 1000, totalPrice: 10.0) // 1000 ml for €10 → €0.01/ml
        let model = makeModelWithVolumeAdditive(ctx: ctx, amount: 100, unit: "ml", density: 1.26, purchase: purchase)

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        // The ingredient is stocked in ml, so 100 ml used × €0.01/ml = €1.00
        #expect(abs(row.cost - 1.0) < 1e-6)
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
        let volume = 100.0.formatted(.number.precision(.fractionLength(0...2)))
        let mass = 126.0.formatted(.number.precision(.fractionLength(0...2)))
        let density = 1.26.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
        #expect(display.conversionNote == "\(volume) ml ≈ \(mass) g, converted using the ingredient's density of \(density) g/ml.")
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
        #expect(note.contains("default density"))
        #expect(note.contains("g/ml"))
        #expect(note.contains("Set a density on the ingredient"))
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
    @Test func wholeBatchBreakdown_VolumeFragrance_ConvertsToMass() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let fragrance = Ingredient(name: "Lavender EO", unit: "ml")
        fragrance.density = 0.89
        ctx.insert(fragrance)

        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.addOil(oil)
        model.setFragranceUnit(.milliliters)
        model.addFragrance(fragrance)
        model.userEditedFragrance(id: model.fragranceDrafts[0].id, amount: 30)

        let row = try #require(model.wholeBatchBreakdown.fragrances.first)
        // 30 ml × 0.89 g/ml = 26.7 g in the batch (oils) unit
        #expect(abs(row.ingredientAmount - 26.7) < 1e-6)
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
    @Test func wholeBatchBreakdown_MassEnteredVolumeInventory_PricesPerInventoryVolume() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let purchase = IngredientPurchase.mock(quantity: 1000, totalPrice: 10.0) // 1000 ml for €10 → €0.01/ml
        // Stocked in ml (density 1.26 g/ml) but entered in the recipe as 126 g.
        let model = makeModelWithVolumeAdditive(ctx: ctx, amount: 126, unit: "g", density: 1.26, purchase: purchase)

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        // 126 g ÷ 1.26 g/ml = 100 ml used × €0.01/ml = €1.00
        #expect(abs(row.cost - 1.0) < 1e-6)
    }
    @Test func wholeBatchBreakdown_KgInventoryAdditive_PricesPerInventoryUnit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let additive = Ingredient(name: "Sodium Lactate", unit: "kg")
        ctx.insert(additive)
        let purchase = IngredientPurchase.mock(quantity: 2, totalPrice: 20.0) // 2 kg for €20 → €10/kg
        purchase.ingredient = additive
        ctx.insert(purchase)

        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.addOil(oil)
        model.addAdditive(additive)
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 500, unit: "g")

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        // 500 g = 0.5 kg × €10/kg = €5.00
        #expect(abs(row.cost - 5.0) < 1e-6)
    }
    @Test func wholeBatchBreakdown_VolumeInventoryOil_PricesPerInventoryVolume() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "ml")
        oil.density = 0.9
        ctx.insert(oil)
        let purchase = IngredientPurchase.mock(quantity: 1000, totalPrice: 10.0) // 1000 ml for €10 → €0.01/ml
        purchase.ingredient = oil
        ctx.insert(purchase)

        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 900
        model.addOil(oil)

        let row = try #require(model.wholeBatchBreakdown.oils.first)
        // 900 g ÷ 0.9 g/ml = 1000 ml used × €0.01/ml = €10.00
        #expect(abs(row.cost - 10.0) < 1e-6)
    }
    @Test func displayedAmount_MassEnteredVolumeInventory_NoteShowsVolumeEquivalent() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModelWithVolumeAdditive(ctx: ctx, amount: 126, unit: "g", density: 1.26)

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        let display = model.displayedAmount(for: row, usesEnteredUnit: true)

        #expect(display.unit == "g")
        #expect(abs(display.amount - 126) < 1e-6)
        let mass = 126.0.formatted(.number.precision(.fractionLength(0...2)))
        let volume = 100.0.formatted(.number.precision(.fractionLength(0...2)))
        let density = 1.26.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
        #expect(display.conversionNote == "\(mass) g ≈ \(volume) ml, converted using the ingredient's density of \(density) g/ml.")
    }
    @Test func displayedAmount_MassEnteredVolumeInventory_DefaultDensity_NoteSaysDefault() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModelWithVolumeAdditive(ctx: ctx, amount: 92, unit: "g", density: nil)

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        let display = model.displayedAmount(for: row, usesEnteredUnit: true)

        let note = try #require(display.conversionNote)
        #expect(note.contains("default density"))
        #expect(note.contains("Set a density on the ingredient"))
    }
    @Test func displayedAmount_PercentageEnteredVolumeInventory_NoteShowsVolumeEquivalent() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModelWithVolumeAdditive(ctx: ctx, amount: 10, unit: "% of oils", density: 1.0)

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        let display = model.displayedAmount(for: row, usesEnteredUnit: true)

        // 10% of 1000 g oils = 100 g, shown in the oil weight unit with the ml equivalent.
        #expect(display.unit == "g")
        #expect(abs(display.amount - 100) < 1e-6)
        let note = try #require(display.conversionNote)
        #expect(note.contains("ml"))
        #expect(note.contains("≈"))
    }
    @Test func displayedAmount_MassEnteredVolumeInventory_NonPositiveDensity_HasNoNote() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModelWithVolumeAdditive(ctx: ctx, amount: 50, unit: "g", density: 0)

        let row = try #require(model.wholeBatchBreakdown.additives.first)
        let display = model.displayedAmount(for: row, usesEnteredUnit: true)

        // A non-positive density can't back a conversion; the amount stands alone.
        #expect(display.unit == "g")
        #expect(display.conversionNote == nil)
    }
}
