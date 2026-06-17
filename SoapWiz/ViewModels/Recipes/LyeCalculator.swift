import Foundation

/// Pure lye/water computation for a recipe draft: single and hybrid (NaOH+KOH)
/// saponification, super-fat discounting, and acid neutralisation. Built on
/// demand from `RecipeFormViewModel` state and shared by the cost and extras
/// calculators.
struct LyeCalculator {
    let oilDrafts: [OilIngredientDraft]
    let additiveDrafts: [IngredientAmountDraft]
    let useHybrid: Bool
    let lyeType: String
    let lyePurity: Double
    let naohPercentage: Double
    let kohPercentage: Double
    let naohPurity: Double
    let kohPurity: Double
    let superFat: Double
    let waterParts: Double
    let weightUnitIsPercentage: Bool
    let totalOilWeight: Double
    let displayWeightUnit: String

    /// g of pure NaOH consumed per gram of acid (anhydrous neutralization
    /// factors, matching the extras table's lye-solution figures).
    static let naohPerGramOfAcid: [(acid: String, factor: Double)] = [
        ("citric acid", 0.625),
        ("ascorbic acid", 0.2020),
        ("lactic acid", 0.5920)
    ]

    /// Molar-mass ratio KOH/NaOH (56.106 / 39.997). KOH neutralises the same acid
    /// as NaOH but, being heavier, more grams are needed by this factor.
    static let kohPerNaOHMass = 56.106 / 39.997

    var oilAmountCalculations: [OilAmountCalculation]? {
        guard !oilDrafts.isEmpty else { return nil }
        guard lyeConfigIsValid else { return nil }

        if weightUnitIsPercentage {
            guard totalOilWeight > 0 else { return nil }
            return oilDrafts.map { draft in
                lyeContribution(weight: totalOilWeight * (draft.amount / 100), draft: draft)
            }
        } else {
            let calcs = oilDrafts.compactMap { draft -> OilAmountCalculation? in
                guard draft.amount > 0 else { return nil }
                return lyeContribution(weight: draft.amount, draft: draft)
            }
            return calcs.isEmpty ? nil : calcs
        }
    }

    /// Whether the active lye configuration can produce a calculation: the purity
    /// of every active lye component must be a valid percentage.
    private var lyeConfigIsValid: Bool {
        func validPurity(_ purity: Double) -> Bool { purity > 0 && purity <= 100 }
        guard useHybrid else { return validPurity(lyePurity) }
        if naohPercentage > 0 && !validPurity(naohPurity) { return false }
        if kohPercentage > 0 && !validPurity(kohPurity) { return false }
        return true
    }

    /// Lye one oil contributes, split into NaOH and KOH and discounted for super
    /// fat. Hybrid scales each lye by its split share and own purity; single lye
    /// uses `lyePurity` and the sap value of the chosen `lyeType`.
    private func lyeContribution(weight: Double, draft: OilIngredientDraft) -> OilAmountCalculation {
        let superFatFactor = 1 - superFat / 100
        let naohSap = draft.ingredient.sapValue ?? 0
        let kohSap = draft.ingredient.kohSapValue ?? 0

        if useHybrid {
            let naohLye = naohPurity > 0
                ? (naohPercentage / 100) * weight * naohSap / (naohPurity / 100) * superFatFactor : 0
            let kohLye = kohPurity > 0
                ? (kohPercentage / 100) * weight * kohSap / (kohPurity / 100) * superFatFactor : 0
            return OilAmountCalculation(id: draft.id, ingredient: draft.ingredient, weight: weight, naohLye: naohLye, kohLye: kohLye)
        }

        let sap = lyeType == "KOH" ? kohSap : naohSap
        let lye = lyePurity > 0 ? weight * sap * superFatFactor / (lyePurity / 100) : 0
        return lyeType == "KOH"
            ? OilAmountCalculation(id: draft.id, ingredient: draft.ingredient, weight: weight, naohLye: 0, kohLye: lye)
            : OilAmountCalculation(id: draft.id, ingredient: draft.ingredient, weight: weight, naohLye: lye, kohLye: 0)
    }

    /// Total NaOH lye, including the NaOH share of acid neutralisation.
    var calculatedNaOHLyeAmount: Double? {
        oilAmountCalculations.map { $0.reduce(0) { $0 + $1.naohLye } + acidNeutralization.naoh }
    }

    /// Total KOH lye, including the KOH share of acid neutralisation.
    var calculatedKOHLyeAmount: Double? {
        oilAmountCalculations.map { $0.reduce(0) { $0 + $1.kohLye } + acidNeutralization.koh }
    }

    var calculatedLyeAmount: Double? {
        let acid = acidNeutralization
        return oilAmountCalculations.map { $0.reduce(0) { $0 + $1.lye } + acid.naoh + acid.koh }
    }

    var calculatedWaterAmount: Double? {
        guard let lye = calculatedLyeAmount else { return nil }
        return lye * waterParts
    }

    /// Total oil weight in the batch (oils) unit.
    var totalOilBatchWeight: Double {
        oilAmountCalculations?.reduce(0) { $0 + $1.weight } ?? 0
    }

    /// Fraction of the lye that is NaOH / KOH, used to split acid neutralisation.
    /// Hybrid follows the configured split; single lye is entirely the chosen
    /// `lyeType`.
    var naohShare: Double { useHybrid ? naohPercentage / 100 : (lyeType == "NaOH" ? 1 : 0) }
    var kohShare: Double { useHybrid ? kohPercentage / 100 : (lyeType == "KOH" ? 1 : 0) }

    /// Purity backing each lye's acid neutralisation: hybrid uses the per-lye
    /// purities, single uses the one `lyePurity`.
    private var effectiveNaOHPurity: Double { useHybrid ? naohPurity : lyePurity }
    private var effectiveKOHPurity: Double { useHybrid ? kohPurity : lyePurity }

    /// Extra lye per (gram of acid × its NaOH neutralisation factor), for each
    /// lye: the lye's split share divided by its purity, with KOH additionally
    /// scaled by the molar-mass ratio (KOH is heavier, so more grams are needed).
    /// `nil` when that lye is absent. These are the actual extra-lye figures —
    /// lye only, no water — matching LyeCalc's "Extra Lye to Neutralize".
    var naohAcidMultiplier: Double? {
        naohShare > 0 && effectiveNaOHPurity > 0 ? naohShare / (effectiveNaOHPurity / 100) : nil
    }
    var kohAcidMultiplier: Double? {
        kohShare > 0 && effectiveKOHPurity > 0 ? Self.kohPerNaOHMass * kohShare / (effectiveKOHPurity / 100) : nil
    }

    /// Extra lye consumed by acid additives, split between NaOH and KOH following
    /// the recipe's lye ratio and each scaled by its own purity. Percentage-unit
    /// drafts are skipped: "% of batch" and "% of liquids" resolve against the
    /// lye amount this value feeds, which would recurse.
    var acidNeutralization: LyeSplit {
        var naoh = 0.0
        var koh = 0.0
        for draft in additiveDrafts {
            guard draft.amount > 0,
                  let factor = Self.naohPerGramOfAcid
                      .first(where: { ingredientNamesMatch(draft.ingredient.name, $0.acid) })?.factor,
                  let batchAmount = IngredientUnitConverter.convert(
                      draft.amount, from: draft.unit, to: displayWeightUnit, density: draft.ingredient.density
                  )?.value
            else { continue }
            if let mult = naohAcidMultiplier { naoh += batchAmount * factor * mult }
            if let mult = kohAcidMultiplier { koh += batchAmount * factor * mult }
        }
        return LyeSplit(naoh: naoh, koh: koh)
    }

    var calculatedAmountRows: [CalculatedAmountRow]? {
        guard let calculations = oilAmountCalculations,
              let totalLye = calculatedLyeAmount,
              let totalWater = calculatedWaterAmount else { return nil }

        let totalOil = calculations.reduce(0.0) { $0 + $1.weight }
        let batchTotal = totalOil + totalLye + totalWater

        func batchPct(_ value: Double) -> Double { batchTotal > 0 ? value / batchTotal * 100 : 0 }

        var rows: [CalculatedAmountRow] = calculations.map { calc in
            let pct = totalOil > 0 ? calc.weight / totalOil * 100 : 0
            return CalculatedAmountRow(label: calc.ingredient.name, weight: calc.weight, pct: pct, isSummary: false)
        }
        rows.append(CalculatedAmountRow(label: "Oils total (batch)", weight: totalOil, pct: batchPct(totalOil), isSummary: true))
        if useHybrid {
            let naoh = calculatedNaOHLyeAmount ?? 0
            let koh = calculatedKOHLyeAmount ?? 0
            rows.append(CalculatedAmountRow(
                label: "KOH (\(PercentageFormatter.string(kohPercentage))%, \(PercentageFormatter.string(kohPurity))% pure)",
                weight: koh, pct: batchPct(koh), isSummary: false
            ))
            rows.append(CalculatedAmountRow(
                label: "NaOH (\(PercentageFormatter.string(naohPercentage))%, \(PercentageFormatter.string(naohPurity))% pure)",
                weight: naoh, pct: batchPct(naoh), isSummary: false
            ))
        } else {
            rows.append(CalculatedAmountRow(
                label: "\(lyeType) (\(PercentageFormatter.string(lyePurity))%, \(PercentageFormatter.string(superFat))% SF)",
                weight: totalLye, pct: batchPct(totalLye), isSummary: false
            ))
        }
        rows.append(CalculatedAmountRow(
            label: "Water (\(PercentageFormatter.string(waterParts)):1)",
            weight: totalWater, pct: batchPct(totalWater), isSummary: false
        ))
        rows.append(CalculatedAmountRow(label: "Batch total", weight: batchTotal, pct: 100, isSummary: true))
        return rows
    }
}
