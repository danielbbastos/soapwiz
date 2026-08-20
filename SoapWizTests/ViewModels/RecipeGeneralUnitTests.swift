import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Non-soap ingredient units", .serialized)
@MainActor
struct RecipeGeneralUnitTests: RecipeFormTestHelpers {

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

    // MARK: - Derived units

    @Test func derivedUnit_NonSoapPercentageMode_IsPercentOfTotal() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.isNonSoapProduct = true
        model.weightUnit = "%"

        #expect(model.derivedUnit(for: makeIngredient(ctx, name: "Mica")) == RecipeUnitOptions.percentOfTotal)
    }

    @Test func derivedUnit_NonSoapAbsoluteMode_IsTheRecipeWeightUnit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.isNonSoapProduct = true
        model.weightUnit = "oz"

        #expect(model.derivedUnit(for: makeIngredient(ctx, name: "Mica")) == "oz")
    }

    /// A component is a component in either kind — no percentage of a wick
    /// means anything.
    @Test func derivedUnit_PieceStockedIngredient_IsAlwaysACount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let jar = makeIngredient(ctx, name: "Glass Jar", unit: RecipeUnitOptions.count)

        let general = RecipeFormViewModel()
        general.isNonSoapProduct = true
        let soap = RecipeFormViewModel()

        #expect(general.derivedUnit(for: jar) == RecipeUnitOptions.count)
        #expect(soap.derivedUnit(for: jar) == RecipeUnitOptions.count)
    }

    @Test func unitLabel_PercentOfTotal_ReadsAsAPlainPercent() {
        let model = RecipeFormViewModel()
        model.isNonSoapProduct = true

        #expect(model.unitLabel(for: RecipeUnitOptions.percentOfTotal) == "%")
    }

    @Test func unitLabel_OtherUnits_AreUnchanged() {
        let model = RecipeFormViewModel()

        #expect(model.unitLabel(for: RecipeUnitOptions.count) == RecipeUnitOptions.count)
        #expect(model.unitLabel(for: "g") == "g")
        #expect(model.unitLabel(for: "% of oils") == "% of oils")
    }

    // MARK: - Reconciling on a change of mode

    @Test func changingMeasurementUnit_RederivesTheMassRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))
        #expect(model.additiveDrafts[0].unit == RecipeUnitOptions.percentOfTotal)

        model.weightUnit = "g"

        #expect(model.additiveDrafts[0].unit == "g")
    }

    @Test func changingMeasurementUnit_LeavesCountRowsAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.addAdditive(makeIngredient(ctx, name: "Glass Jar", unit: RecipeUnitOptions.count))

        model.weightUnit = "g"

        #expect(model.additiveDrafts[0].unit == RecipeUnitOptions.count)
    }

    /// Rows added while the recipe was soap carry a unit non-soap can't express,
    /// so switching pulls them onto the one scale.
    @Test func switchingToNonSoap_RederivesTheMassRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.isNonSoapProduct = false
        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))
        #expect(model.additiveDrafts[0].unit == "g")

        model.isNonSoapProduct = true

        #expect(model.additiveDrafts[0].unit == RecipeUnitOptions.percentOfTotal)
    }

    /// Soap can't express "% of total", so only that is rewritten on the way
    /// back — a deliberately chosen "% of oils" survives the round trip.
    @Test func switchingBackToSoap_RewritesOnlyWhatSoapCannotExpress() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.isNonSoapProduct = false
        model.addAdditive(makeIngredient(ctx, name: "Sodium Lactate"))
        model.updateAdditive(id: model.additiveDrafts[0].id, unit: "% of oils")
        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))
        model.updateAdditive(id: model.additiveDrafts[1].id, unit: "ml")

        model.isNonSoapProduct = true
        #expect(model.additiveDrafts.allSatisfy { $0.unit == RecipeUnitOptions.percentOfTotal })

        model.isNonSoapProduct = false

        #expect(model.additiveDrafts.allSatisfy { $0.unit == "g" })
    }

    @Test func soapRecipe_ChangingMeasurementUnit_LeavesItsUnitsAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.addAdditive(makeIngredient(ctx, name: "Sodium Lactate"))
        model.updateAdditive(id: model.additiveDrafts[0].id, unit: "% of oils")

        model.weightUnit = "g"

        #expect(model.additiveDrafts[0].unit == "% of oils")
    }

    // MARK: - Default unit

    @Test func defaultAdditiveUnit_NonSoapPercentageMode_IsPercentOfTotal() {
        let model = RecipeFormViewModel()
        model.isNonSoapProduct = true
        model.weightUnit = "%"

        #expect(model.defaultAdditiveUnit == RecipeUnitOptions.percentOfTotal)
    }

    @Test func defaultAdditiveUnit_SoapPercentageMode_StaysGrams() {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"

        #expect(model.defaultAdditiveUnit == "g")
    }

    @Test func addAdditive_NonSoapPercentageMode_StartsAsPercentOfTotal() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)

        model.addAdditive(makeIngredient(ctx, name: "Activated Charcoal"))

        #expect(model.additiveDrafts[0].unit == RecipeUnitOptions.percentOfTotal)
    }

    /// No percentage of a wick means anything, so a piece-stocked ingredient
    /// starts as a count whatever mode the recipe is in.
    @Test func addAdditive_IngredientStockedByThePiece_StartsAsCount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)

        model.addAdditive(makeIngredient(ctx, name: "Glass Jar", unit: RecipeUnitOptions.count))

        #expect(model.additiveDrafts[0].unit == RecipeUnitOptions.count)
    }

    // MARK: - Fragrance units

    @Test func availableFragranceUnits_SoapRecipe_OffersEveryUnit() {
        let model = RecipeFormViewModel()

        #expect(model.availableFragranceUnits == FragranceUnit.allCases)
    }

    /// Both resolve against the lye and the water, which a general recipe has
    /// none of.
    @Test func availableFragranceUnits_NonSoapRecipe_DropsTheLyeBasedUnits() {
        let model = RecipeFormViewModel()
        model.isNonSoapProduct = true

        #expect(!model.availableFragranceUnits.contains(.percentOfBatch))
        #expect(!model.availableFragranceUnits.contains(.percentOfLiquids))
        #expect(model.availableFragranceUnits.contains(.percentOfFragrances))
        #expect(model.availableFragranceUnits.contains(.grams))
    }

    @Test func switchingToNonSoap_RewritesAFragranceUnitItCannotExpress() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.isNonSoapProduct = false
        model.addFragrance(makeIngredient(ctx, name: "Lavender EO", category: IngredientCategory.Name.fragrances))
        model.setFragranceUnit(.percentOfBatch)

        model.isNonSoapProduct = true

        #expect(model.fragranceUnit == .percentOfOils)
        #expect(model.fragranceDrafts.allSatisfy { $0.unit == "% of oils" })
    }

    /// Reconciling preserves the entered numbers — unlike `setFragranceUnit`,
    /// which re-expresses them for the new basis.
    @Test func switchingToNonSoap_KeepsTheFragranceAmounts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.isNonSoapProduct = false
        model.addFragrance(makeIngredient(ctx, name: "Lavender EO", category: IngredientCategory.Name.fragrances))
        model.setFragranceUnit(.percentOfBatch)
        model.userEditedFragrance(id: model.fragranceDrafts[0].id, amount: 4)

        model.isNonSoapProduct = true

        #expect(model.fragranceDrafts[0].amount == 4)
    }

    @Test func switchingToNonSoap_LeavesAnExpressibleFragranceUnitAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeGeneralModel(ctx)
        model.isNonSoapProduct = false
        model.addFragrance(makeIngredient(ctx, name: "Lavender EO", category: IngredientCategory.Name.fragrances))
        model.setFragranceUnit(.grams)

        model.isNonSoapProduct = true

        #expect(model.fragranceUnit == .grams)
    }
}
