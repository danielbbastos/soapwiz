import Foundation
import SwiftData

/// Pure cost/breakdown computation for a recipe draft. Amounts are expressed in
/// the batch (oils) unit for display; cost is always derived from the
/// gram-equivalent so it stays correct regardless of the chosen oil weight unit.
struct RecipeCostCalculator {
    let lye: LyeCalculator
    let additiveDrafts: [IngredientAmountDraft]
    let fragranceDrafts: [IngredientAmountDraft]
    let fragranceUnit: FragranceUnit
    let fragrancePercentage: Double
    let displayWeightUnit: String
    let lyeIngredient: Ingredient?
    let kohLyeIngredient: Ingredient?

    private var useHybrid: Bool { lye.useHybrid }
    private var lyeType: String { lye.lyeType }

    func breakdownAndCost(for product: RecipeProductDraft, batch: ProductCostBreakdown) -> ProductCostBreakdown {
        let unit = ProductUnit(rawValue: product.unitSymbol)
        if unit == .wholeBatch {
            return scaleBreakdown(batch, by: 1)
        }
        let size = product.size
        guard size > 0 else { return ProductCostBreakdown() }

        if unit == .partsOfBatch {
            return scaleBreakdown(batch, by: 1 / size)
        }
        guard let unit, let perUnit = unit.gramsPerUnit else { return ProductCostBreakdown() }
        let productGrams = perUnit * size
        let batchGrams = gramsForCost(batchTotalWeight(from: batch))
        let rawShare = batchGrams > 0 ? productGrams / batchGrams : 0
        var result = scaleBreakdown(batch, by: min(rawShare, 1))
        result.exceedsBatchWeight = rawShare > 1
        return result
    }

    func breakdownAndCost(for product: RecipeProductDraft) -> ProductCostBreakdown {
        breakdownAndCost(for: product, batch: wholeBatchBreakdown)
    }

    var wholeBatchBreakdown: ProductCostBreakdown {
        let oils = oilBatchBreakdown
        let additives = additiveBatchBreakdown
        let fragrances = fragranceBatchBreakdown
        let lyeRows = lyeBatchBreakdown
        let total = (oils + additives + fragrances + lyeRows).reduce(0) { $0 + $1.cost }
        return ProductCostBreakdown(oils: oils, additives: additives, fragrances: fragrances, lye: lyeRows, total: total)
    }

    private var oilBatchBreakdown: [IngredientProductBreakdown] {
        guard let calcs = lye.oilAmountCalculations else { return [] }
        return calcs.map { calc in
            IngredientProductBreakdown(
                ingredient: calc.ingredient,
                ingredientAmount: calc.weight,
                cost: cost(ofBatchAmount: calc.weight, for: calc.ingredient)
            )
        }
    }

    private var additiveBatchBreakdown: [IngredientProductBreakdown] {
        breakdown(for: additiveDrafts)
    }

    /// For `% of fragrances` the rows are shares of the blend, so they can't be
    /// resolved one at a time: the total load (`fragrancePercentage` of the
    /// oils) is computed once and split across the rows in proportion to their
    /// amounts. Normalising by the actual sum rather than assuming 100 keeps
    /// the maths sane while the user is mid-edit and the rows don't yet add up.
    private var fragranceBatchBreakdown: [IngredientProductBreakdown] {
        guard fragranceUnit == .percentOfFragrances else {
            return breakdown(for: fragranceDrafts)
        }
        let load = lye.totalOilBatchWeight * fragrancePercentage / 100
        let shareSum = fragranceDrafts.reduce(0) { $0 + $1.amount }
        guard load > 0, shareSum > 0 else { return [] }
        return fragranceDrafts.compactMap { draft in
            guard draft.amount > 0 else { return nil }
            let batchAmount = load * (draft.amount / shareSum)
            return IngredientProductBreakdown(
                ingredient: draft.ingredient,
                ingredientAmount: batchAmount,
                cost: cost(ofBatchAmount: batchAmount, for: draft.ingredient)
            )
        }
    }

    /// Breakdown rows for additive/fragrance drafts, with amounts in the batch
    /// (oils) unit and cost derived from the gram-equivalent.
    private func breakdown(for drafts: [IngredientAmountDraft]) -> [IngredientProductBreakdown] {
        drafts.compactMap { draft in
            guard draft.amount > 0 else { return nil }
            // A count is priced straight off the inventory unit — there is no
            // weight to convert through, and going via the gram fallback would
            // price one jar as one gram of jar.
            if RecipeUnitOptions.isCount(draft.unit) {
                return IngredientProductBreakdown(
                    ingredient: draft.ingredient,
                    ingredientAmount: draft.amount,
                    cost: draft.amount * weightedCostPerUnit(for: draft.ingredient),
                    isCountBased: true
                )
            }
            guard let batchAmount = amountInBatchUnit(
                amount: draft.amount, unit: draft.unit, density: draft.ingredient.density
            ) else { return nil }
            return IngredientProductBreakdown(
                ingredient: draft.ingredient,
                ingredientAmount: batchAmount,
                cost: cost(ofBatchAmount: batchAmount, for: draft.ingredient)
            )
        }
    }

    private var lyeBatchBreakdown: [IngredientProductBreakdown] {
        func row(_ ingredient: Ingredient?, _ amount: Double?) -> IngredientProductBreakdown? {
            guard let ingredient, let amount, amount > 0 else { return nil }
            return IngredientProductBreakdown(
                ingredient: ingredient,
                ingredientAmount: amount,
                cost: cost(ofBatchAmount: amount, for: ingredient)
            )
        }
        guard useHybrid else {
            let ingredient = lyeType == "KOH" ? kohLyeIngredient : lyeIngredient
            return [row(ingredient, lye.calculatedLyeAmount)].compactMap { $0 }
        }
        return [
            row(lyeIngredient, lye.calculatedNaOHLyeAmount),
            row(kohLyeIngredient, lye.calculatedKOHLyeAmount)
        ].compactMap { $0 }
    }

    /// Total batch weight in the batch (oils) unit: oils + additives + fragrances
    /// + lye + water. Fragrance oil is real mass, so leaving it out shrinks the
    /// denominator and over-allocates cost to every fixed-size product.
    ///
    /// Lye comes from the calculator rather than `batch.lye`, whose rows only
    /// exist once a lye `Ingredient` has been resolved; the mass is in the pot
    /// either way.
    ///
    /// Excludes the Failor neutraliser solution (`LyeCalculator.cfmNeutralizerRows`):
    /// it is a dosing recommendation rather than a recipe line item, and it is
    /// absent from `wholeBatchBreakdown` and batch requirements too. A CFM batch's
    /// weight is therefore understated by the neutraliser dose.
    func batchTotalWeight(from batch: ProductCostBreakdown) -> Double {
        // Counts carry no mass, so they are left out of every weight total.
        let additives = batch.additives.lazy.filter { !$0.isCountBased }.reduce(0) { $0 + $1.ingredientAmount }
        let fragrances = batch.fragrances.lazy.filter { !$0.isCountBased }.reduce(0) { $0 + $1.ingredientAmount }
        let lyeAmount = lye.calculatedLyeAmount ?? 0
        let water = lye.calculatedWaterAmount ?? 0
        return lye.totalOilBatchWeight + additives + fragrances + lyeAmount + water
    }

    private func scaleBreakdown(_ source: ProductCostBreakdown, by factor: Double) -> ProductCostBreakdown {
        func scale(_ rows: [IngredientProductBreakdown]) -> [IngredientProductBreakdown] {
            rows.map {
                IngredientProductBreakdown(
                    ingredient: $0.ingredient,
                    ingredientAmount: $0.ingredientAmount * factor,
                    cost: $0.cost * factor,
                    // Carried through, or a scaled count would render as a
                    // weight in the per-product breakdown.
                    isCountBased: $0.isCountBased
                )
            }
        }
        let oils = scale(source.oils)
        let additives = scale(source.additives)
        let fragrances = scale(source.fragrances)
        let lyeRows = scale(source.lye)
        let total = (oils + additives + fragrances + lyeRows).reduce(0) { $0 + $1.cost }
        return ProductCostBreakdown(oils: oils, additives: additives, fragrances: fragrances, lye: lyeRows, total: total)
    }

    /// Grams equivalent of an amount already expressed in the batch (oils) unit,
    /// used for cost. Falls back to the amount unchanged if the unit isn't
    /// convertible. No density is passed: the batch unit is always a mass, so the
    /// crossing never needs one.
    private func gramsForCost(_ batchAmount: Double) -> Double {
        IngredientUnitConverter.convert(batchAmount, from: displayWeightUnit, to: "g", density: nil)?.value ?? batchAmount
    }

    /// Cost of an amount expressed in the batch (oils) unit: the amount is
    /// converted into the ingredient's inventory unit — volume inventories cross
    /// via the ingredient's density, mirroring batch creation — and priced at
    /// the purchase-weighted cost per inventory unit. Falls back to the gram
    /// equivalent when the units aren't convertible (e.g. "un").
    private func cost(ofBatchAmount batchAmount: Double, for ingredient: Ingredient) -> Double {
        let inInventoryUnit = IngredientUnitConverter
            .convert(batchAmount, from: displayWeightUnit, to: ingredient.unit, density: ingredient.density)?
            .value ?? gramsForCost(batchAmount)
        return inInventoryUnit * weightedCostPerUnit(for: ingredient)
    }

    /// The amount and unit to present for a cost-breakdown row. Additives and
    /// fragrances (`usesEnteredUnit`) are shown in the unit the user picked when
    /// that's a mass or volume unit; percentage entries, oils, and lye use the
    /// oil weight unit. Breakdown amounts are stored in the oil weight unit, so
    /// entered units are converted back — volume units via the ingredient's
    /// density, surfaced in `conversionNote` alongside the mass equivalent.
    func displayedAmount(for row: IngredientProductBreakdown, usesEnteredUnit: Bool) -> BreakdownAmountDisplay {
        if row.isCountBased {
            return BreakdownAmountDisplay(
                amount: row.ingredientAmount, unit: RecipeUnitOptions.count, conversionNote: nil
            )
        }
        if usesEnteredUnit, let unit = enteredUnit(for: row.ingredient),
           let result = IngredientUnitConverter.convert(
               row.ingredientAmount, from: displayWeightUnit, to: unit, density: row.ingredient.density
           ) {
            let note: String?
            if let density = result.density {
                note = conversionNote(
                    from: Quantity(amount: result.value, unit: unit),
                    to: Quantity(amount: row.ingredientAmount, unit: displayWeightUnit),
                    density: density, usedDefaultDensity: result.usedDefaultDensity
                )
            } else {
                note = inventoryUnitNote(for: row.ingredient, amount: result.value, unit: unit)
            }
            return BreakdownAmountDisplay(amount: result.value, unit: unit, conversionNote: note)
        }
        return BreakdownAmountDisplay(
            amount: row.ingredientAmount,
            unit: displayWeightUnit,
            conversionNote: inventoryUnitNote(for: row.ingredient, amount: row.ingredientAmount, unit: displayWeightUnit)
        )
    }

    /// Note for a row shown in a mass unit while the ingredient is stocked in a
    /// volume unit: the displayed mass crosses to the inventory volume the cost
    /// is priced on, e.g. "15 g ≈ 16.3 ml". `nil` when no crossing happens.
    private func inventoryUnitNote(for ingredient: Ingredient, amount: Double, unit: String) -> String? {
        guard IngredientUnitConverter.isVolume(ingredient.unit),
              let result = IngredientUnitConverter.convert(
                  amount, from: unit, to: ingredient.unit, density: ingredient.density
              ),
              let density = result.density else { return nil }
        return conversionNote(
            from: Quantity(amount: amount, unit: unit),
            to: Quantity(amount: result.value, unit: ingredient.unit),
            density: density, usedDefaultDensity: result.usedDefaultDensity
        )
    }

    /// Explains the volume↔mass crossing behind a breakdown row — the displayed
    /// amount, its equivalent on the other side of the crossing, and the density
    /// used — for the row's info popover.
    private func conversionNote(
        from source: Quantity, to equivalent: Quantity,
        density: Double, usedDefaultDensity: Bool
    ) -> String {
        let amountText = source.amount.formatted(.number.precision(.fractionLength(0...2)))
        let equivalentText = equivalent.amount.formatted(.number.precision(.fractionLength(0...2)))
        let densityText = density.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
        let crossing = "\(amountText) \(source.unit) ≈ \(equivalentText) \(equivalent.unit)"
        if usedDefaultDensity {
            return crossing + ", converted using the default density of \(densityText) g/ml. "
                + "Set a density on the ingredient for a more accurate conversion."
        }
        return crossing + ", converted using the ingredient's density of \(densityText) g/ml."
    }

    private func enteredUnit(for ingredient: Ingredient) -> String? {
        let id = ingredient.persistentModelID
        if let additive = additiveDrafts.first(where: { $0.ingredient.persistentModelID == id }) { return additive.unit }
        if let fragrance = fragranceDrafts.first(where: { $0.ingredient.persistentModelID == id }) { return fragrance.unit }
        return nil
    }

    /// Expresses an ingredient amount in the batch (oils) unit. Mass and volume
    /// units flow through the shared converter — volume entries (ml, L) cross to
    /// mass via the ingredient's density (default fallback when none is recorded);
    /// percentages resolve against the relevant batch quantity (already in the
    /// oils unit).
    private func amountInBatchUnit(amount: Double, unit: String, density: Double?) -> Double? {
        if let converted = IngredientUnitConverter.convert(amount, from: unit, to: displayWeightUnit, density: density) {
            return converted.value
        }
        let fraction = amount / 100
        let totalOil = lye.totalOilBatchWeight
        switch unit {
        case "% of oils":
            return totalOil > 0 ? totalOil * fraction : nil
        // "% of batch" resolves against oils + lye + water, deliberately not
        // `batchTotalWeight`: additives and fragrances are what this is sizing,
        // and a fragrance can itself be entered as a percentage, so including
        // them would be circular. Do not "fix" this to match batchTotalWeight.
        case "% of batch":
            guard let lyeAmount = lye.calculatedLyeAmount, let water = lye.calculatedWaterAmount else { return nil }
            return (totalOil + lyeAmount + water) * fraction
        case "% of liquids":
            guard let lyeAmount = lye.calculatedLyeAmount, let water = lye.calculatedWaterAmount else { return nil }
            return (lyeAmount + water) * fraction
        case RecipeUnitOptions.percentOfTotal:
            let base = lye.declaredTotalWeight
            return base > 0 ? base * fraction : nil
        default: return nil
        }
    }

    private func weightedCostPerUnit(for ingredient: Ingredient) -> Double {
        let purchases = ingredient.purchases.filter { $0.quantity > 0 }
        guard !purchases.isEmpty else { return 0 }
        let totalCost = purchases.reduce(0.0) { $0 + $1.totalPrice }
        let totalQty = purchases.reduce(0.0) { $0 + $1.quantity }
        return totalQty > 0 ? totalCost / totalQty : 0
    }
}
