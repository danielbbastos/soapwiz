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
    let useCFM: Bool
    let cfmNeutralizer: CFMNeutralizer

    /// Fraction of the soap weight dosed as the Failor neutraliser solution
    /// (¾ oz per lb of soap = 0.75/16).
    static let cfmNeutralizerSolutionFraction = 0.75 / 16

    /// Excess-lye multiplier the Catherine Failor method applies in place of the
    /// super-fat discount: 0% super fat plus 10% excess lye → ×1.10.
    static let cfmExcessLyeFactor = 1.10

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

    /// How the soap is classified from the lye configuration. Gates the Catherine
    /// Failor method, which only applies to non-solid soaps.
    var soapType: SoapType {
        SoapType.classify(useHybrid: useHybrid, naohPercentage: naohPercentage, lyeType: lyeType)
    }

    /// Whether the Catherine Failor method is in effect: requested and the soap
    /// isn't a solid bar.
    var cfmActive: Bool { useCFM && soapType != .solid }

    /// Normal lye factor — the super-fat discount applied to full saponification.
    private var superFatFactor: Double { 1 - superFat / 100 }

    /// Factor used for the *needed* (and costed) lye: the Failor method overrides
    /// the super-fat discount with a 10% excess instead; otherwise it's the
    /// normal super-fat discount.
    var neededLyeFactor: Double { cfmActive ? Self.cfmExcessLyeFactor : superFatFactor }

    /// Per-oil lye contributions at a given lye factor. Oil weights are factor
    /// independent; only the lye scales, so callers can ask for the needed,
    /// normal, or full-saponification basis from the same resolution.
    private func oilCalculations(factor: Double) -> [OilAmountCalculation]? {
        guard !oilDrafts.isEmpty else { return nil }
        guard lyeConfigIsValid else { return nil }

        if weightUnitIsPercentage {
            guard totalOilWeight > 0 else { return nil }
            return oilDrafts.map { draft in
                lyeContribution(weight: totalOilWeight * (draft.amount / 100), draft: draft, factor: factor)
            }
        } else {
            let calcs = oilDrafts.compactMap { draft -> OilAmountCalculation? in
                guard draft.amount > 0 else { return nil }
                return lyeContribution(weight: draft.amount, draft: draft, factor: factor)
            }
            return calcs.isEmpty ? nil : calcs
        }
    }

    /// Per-oil lye at the *needed* factor — drives the displayed lye amounts and
    /// the recipe cost (the lye actually added).
    var oilAmountCalculations: [OilAmountCalculation]? {
        oilCalculations(factor: neededLyeFactor)
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

    /// Lye one oil contributes, split into NaOH and KOH and scaled by `factor`
    /// (super-fat discount or Failor excess). Hybrid scales each lye by its split
    /// share and own purity; single lye uses `lyePurity` and the sap value of the
    /// chosen `lyeType`.
    private func lyeContribution(weight: Double, draft: OilIngredientDraft, factor: Double) -> OilAmountCalculation {
        let naohSap = draft.ingredient.sapValue ?? 0
        let kohSap = draft.ingredient.kohSapValue ?? 0

        if useHybrid {
            let naohLye = naohPurity > 0
                ? (naohPercentage / 100) * weight * naohSap / (naohPurity / 100) * factor : 0
            let kohLye = kohPurity > 0
                ? (kohPercentage / 100) * weight * kohSap / (kohPurity / 100) * factor : 0
            return OilAmountCalculation(id: draft.id, ingredient: draft.ingredient, weight: weight, naohLye: naohLye, kohLye: kohLye)
        }

        let sap = lyeType == "KOH" ? kohSap : naohSap
        let lye = lyePurity > 0 ? weight * sap * factor / (lyePurity / 100) : 0
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

    /// Total lye at the recipe's normal super fat, ignoring any Failor excess.
    /// Water is sized from this so the 10% excess lye doesn't inflate the water
    /// (matching LightCalc); without CFM it equals `calculatedLyeAmount`.
    var normalSuperFatLyeAmount: Double? {
        oilCalculations(factor: superFatFactor)
            .map { $0.reduce(0) { $0 + $1.lye } + acidNeutralization.naoh + acidNeutralization.koh }
    }

    var calculatedWaterAmount: Double? {
        guard let lye = normalSuperFatLyeAmount else { return nil }
        return lye * waterParts
    }

    /// Soap weight before cooking: oils + full-saponification lye (0% super fat,
    /// no excess) + batch water. Used as the base for the Failor neutraliser
    /// solution dose. `nil` until the recipe has oils.
    var soapWeightPreCook: Double? {
        guard let fullLye = oilCalculations(factor: 1)
            .map({ $0.reduce(0) { $0 + $1.lye } + acidNeutralization.naoh + acidNeutralization.koh }),
              let water = calculatedWaterAmount else { return nil }
        return totalOilBatchWeight + fullLye + water
    }

    /// The two Failor neutraliser rows (the solid and its dissolving water) for
    /// the calculated-amounts table, or `nil` when CFM isn't active. Display-only:
    /// the excess lye is neutralised during the cook, so these are recommendations
    /// rather than part of the saponified soap weight.
    var cfmNeutralizerRows: (solid: CalculatedAmountRow, water: CalculatedAmountRow)? {
        guard cfmActive, let soapWeight = soapWeightPreCook, soapWeight > 0 else { return nil }
        let solution = soapWeight * Self.cfmNeutralizerSolutionFraction
        let solidFraction = cfmNeutralizer.solidFraction
        let solid = solution * solidFraction
        let water = solution * (1 - solidFraction)
        let solidPct = Int((solidFraction * 100).rounded())
        let waterPct = 100 - solidPct
        return (
            solid: CalculatedAmountRow(
                label: "\(cfmNeutralizer.displayName) (\(solidPct)% of Solution)",
                weight: solid, pct: 0, isSummary: false
            ),
            water: CalculatedAmountRow(
                label: "Water for \(cfmNeutralizer.displayName) Solution (\(waterPct)% of Solution)",
                weight: water, pct: 0, isSummary: false
            )
        )
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

        // Under the Failor method the lye is taken at 0% super fat + 10% excess,
        // so the per-lye rows carry that note instead of the purity/SF detail.
        func lyeLabel(_ lye: String, detail: @autoclosure () -> String) -> String {
            let qualifier = cfmActive ? "0% Superfat + 10% Excess Lye" : detail()
            return "\(lye) (\(qualifier))"
        }
        func pct(_ value: Double) -> String { PercentageFormatter.string(value) }

        if useHybrid {
            let naoh = calculatedNaOHLyeAmount ?? 0
            let koh = calculatedKOHLyeAmount ?? 0
            rows.append(CalculatedAmountRow(
                label: lyeLabel("KOH", detail: "\(pct(kohPercentage))%, \(pct(kohPurity))% pure"),
                weight: koh, pct: batchPct(koh), isSummary: false
            ))
            rows.append(CalculatedAmountRow(
                label: lyeLabel("NaOH", detail: "\(pct(naohPercentage))%, \(pct(naohPurity))% pure"),
                weight: naoh, pct: batchPct(naoh), isSummary: false
            ))
        } else {
            rows.append(CalculatedAmountRow(
                label: lyeLabel(lyeType, detail: "\(pct(lyePurity))%, \(pct(superFat))% SF"),
                weight: totalLye, pct: batchPct(totalLye), isSummary: false
            ))
        }

        // Failor neutraliser solution (display-only recommendation).
        if let neutralizer = cfmNeutralizerRows {
            rows.append(CalculatedAmountRow(
                label: neutralizer.solid.label, weight: neutralizer.solid.weight,
                pct: batchPct(neutralizer.solid.weight), isSummary: false
            ))
            rows.append(CalculatedAmountRow(
                label: neutralizer.water.label, weight: neutralizer.water.weight,
                pct: batchPct(neutralizer.water.weight), isSummary: false
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
