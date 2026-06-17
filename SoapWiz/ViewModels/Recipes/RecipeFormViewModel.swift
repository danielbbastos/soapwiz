import SwiftUI
import SwiftData

struct OilIngredientDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var amount: Double = 0
    var isLocked: Bool = false
}

struct IngredientAmountDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var amount: Double = 0
    var unit: String
    var isLocked: Bool = false
}

struct FragranceTarget {
    /// e.g. "45 g (3%)"
    let text: String
    /// The configured fragrance percentage, for the explanatory tooltip.
    let percentage: Double
    /// Whether the entered fragrance total exceeds the recommended target.
    let isOverTarget: Bool
}

struct RecipeProductDraft: Identifiable {
    let id = UUID()
    var size: Double = 0
    var unitSymbol: String = ""
    var modelID: PersistentIdentifier? = nil
}

struct IngredientProductBreakdown {
    let ingredient: Ingredient
    let ingredientAmount: Double
    let cost: Double
}

struct BreakdownAmountDisplay {
    let amount: Double
    let unit: String
    /// Explanation of the volume↔mass crossing behind the amount, shown in an
    /// info popover, e.g. "100 ml ≈ 126 g, converted using the ingredient's
    /// density of 1.26 g/ml.". `nil` when no density was used.
    let conversionNote: String?
}

struct ProductCostBreakdown {
    var oils: [IngredientProductBreakdown] = []
    var additives: [IngredientProductBreakdown] = []
    var fragrances: [IngredientProductBreakdown] = []
    var lye: [IngredientProductBreakdown] = []
    var total: Double = 0
    var exceedsBatchWeight: Bool = false
}

struct OilAmountCalculation: Identifiable {
    let id: UUID
    let ingredient: Ingredient
    let weight: Double
    /// Lye contributed by this oil, already discounted for super fat. Split so
    /// the hybrid path can price NaOH and KOH separately; the single path puts
    /// everything in `naohLye`.
    let naohLye: Double
    let kohLye: Double
    var lye: Double { naohLye + kohLye }
}

struct CalculatedAmountRow: Identifiable {
    let id = UUID()
    let label: String
    let weight: Double
    let pct: Double
    let isSummary: Bool
}

struct ExtraSectionARow: Identifiable {
    let id = UUID()
    let label: String
    let val1: Double
    let val2: Double
    let val3: Double
    let naohLyeSolution: (v1: Double, v2: Double, v3: Double)?
    let kohLyeSolution: (v1: Double, v2: Double, v3: Double)?

    init(label: String, val1: Double, val2: Double, val3: Double,
         naohLyeSolution: (v1: Double, v2: Double, v3: Double)? = nil,
         kohLyeSolution: (v1: Double, v2: Double, v3: Double)? = nil) {
        self.label = label
        self.val1 = val1
        self.val2 = val2
        self.val3 = val3
        self.naohLyeSolution = naohLyeSolution
        self.kohLyeSolution = kohLyeSolution
    }
}

struct ExtraSectionBRow: Identifiable {
    let id = UUID()
    let label: String
    let minValue: Double
    let maxValue: Double?
    let naohLyeSolution: Double?
    let kohLyeSolution: Double?

    init(label: String, minValue: Double, maxValue: Double? = nil,
         naohLyeSolution: Double? = nil, kohLyeSolution: Double? = nil) {
        self.label = label
        self.minValue = minValue
        self.maxValue = maxValue
        self.naohLyeSolution = naohLyeSolution
        self.kohLyeSolution = kohLyeSolution
    }
}

@Observable
final class RecipeFormViewModel {
    var name: String = ""
    var desc: String = ""
    var weightUnit: String = "%"
    var totalOilWeight: Double = 1000
    var oilWeightUnit: String = "g"
    var lyeType: String = "NaOH"
    var lyePurity: Double = 99
    var waterParts: Double = 1.5
    var superFat: Double = 5
    var oilDrafts: [OilIngredientDraft] = []
    var additiveDrafts: [IngredientAmountDraft] = []
    var fragranceDrafts: [IngredientAmountDraft] = []
    var productDrafts: [RecipeProductDraft] = []
    var fragrancePercentage: Double = 3
    var useHybrid: Bool = false
    var kohPercentage: Double = 90
    var naohPercentage: Double = 10
    var kohPurity: Double = 90
    var naohPurity: Double = 99
    var lyeIngredient: Ingredient?
    var kohLyeIngredient: Ingredient?

    @ObservationIgnored
    private var editingRecipe: Recipe?

    init() {
        productDrafts = [Self.defaultProductDraft()]
    }

    private static func defaultProductDraft() -> RecipeProductDraft {
        RecipeProductDraft(size: 1, unitSymbol: ProductUnit.partsOfBatch.rawValue)
    }

    var weightUnitIsPercentage: Bool { weightUnit == "%" }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var totalPercentage: Double {
        oilDrafts.reduce(0) { $0 + $1.amount }
    }

    var totalPercentageText: String { formatPercentage(totalPercentage) }

    var displayWeightUnit: String {
        weightUnitIsPercentage ? oilWeightUnit : weightUnit
    }

    /// Default unit for new fragrance rows: percentage-of-oils when the recipe is
    /// measured in percentages, otherwise the recipe's oil weight unit.
    var defaultFragranceUnit: String {
        weightUnitIsPercentage ? "% of oils" : weightUnit
    }

    /// Default unit for new additive rows. Additives are conventionally entered
    /// as a weight, so they default to grams in percentage mode (rather than
    /// "% of oils") to avoid silently applying a percentage of the oils.
    var defaultAdditiveUnit: String {
        weightUnitIsPercentage ? "g" : weightUnit
    }

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

    var soapType: SoapType {
        SoapType.classify(
            useHybrid: useHybrid,
            naohPercentage: naohPercentage,
            kohPercentage: kohPercentage,
            lyeType: lyeType
        )
    }

    /// Standard single-lye purities: NaOH ships near-anhydrous (~99%), KOH is
    /// hygroscopic and sold at ~90%.
    static let defaultNaOHPurity = 99.0
    static let defaultKOHPurity = 90.0

    /// Switches the single lye type, moving `lyePurity` to the new lye's standard
    /// default — but only when it still holds the other lye's default, so a value
    /// the user set deliberately is preserved.
    func setLyeType(_ type: String) {
        if type == "KOH", lyePurity == Self.defaultNaOHPurity {
            lyePurity = Self.defaultKOHPurity
        } else if type == "NaOH", lyePurity == Self.defaultKOHPurity {
            lyePurity = Self.defaultNaOHPurity
        }
        lyeType = type
    }

    /// Sets the KOH share (clamped 0–100) and keeps NaOH as the complement so the
    /// split always sums to 100.
    func setKOHPercentage(_ value: Double) {
        let clamped = min(max(value, 0), 100)
        kohPercentage = clamped
        naohPercentage = 100 - clamped
    }

    /// Sets the NaOH share (clamped 0–100), keeping KOH as the complement.
    func setNaOHPercentage(_ value: Double) {
        let clamped = min(max(value, 0), 100)
        naohPercentage = clamped
        kohPercentage = 100 - clamped
    }

    /// g of pure NaOH consumed per gram of acid (anhydrous neutralization
    /// factors, matching the extras table's lye-solution figures).
    private static let naohPerGramOfAcid: [(acid: String, factor: Double)] = [
        ("citric acid", 0.625),
        ("ascorbic acid", 0.2020),
        ("lactic acid", 0.5920),
    ]

    /// Molar-mass ratio KOH/NaOH (56.106 / 39.997). KOH neutralises the same acid
    /// as NaOH but, being heavier, more grams are needed by this factor.
    static let kohPerNaOHMass = 56.106 / 39.997

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
    private var naohAcidMultiplier: Double? {
        naohShare > 0 && effectiveNaOHPurity > 0 ? naohShare / (effectiveNaOHPurity / 100) : nil
    }
    private var kohAcidMultiplier: Double? {
        kohShare > 0 && effectiveKOHPurity > 0 ? Self.kohPerNaOHMass * kohShare / (effectiveKOHPurity / 100) : nil
    }

    /// Extra lye consumed by acid additives, split between NaOH and KOH following
    /// the recipe's lye ratio and each scaled by its own purity. Percentage-unit
    /// drafts are skipped: "% of batch" and "% of liquids" resolve against the
    /// lye amount this value feeds, which would recurse.
    private var acidNeutralization: (naoh: Double, koh: Double) {
        var naoh = 0.0
        var koh = 0.0
        for draft in additiveDrafts {
            guard draft.amount > 0,
                  let factor = Self.naohPerGramOfAcid
                      .first(where: { Self.namesMatch(draft.ingredient.name, $0.acid) })?.factor,
                  let batchAmount = IngredientUnitConverter.convert(
                      draft.amount, from: draft.unit, to: displayWeightUnit, density: draft.ingredient.density
                  )?.value
            else { continue }
            if let mult = naohAcidMultiplier { naoh += batchAmount * factor * mult }
            if let mult = kohAcidMultiplier { koh += batchAmount * factor * mult }
        }
        return (naoh, koh)
    }

    var calculatedWaterAmount: Double? {
        guard let lye = calculatedLyeAmount else { return nil }
        return lye * waterParts
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
                label: "KOH (\(formatPercentage(kohPercentage))%, \(formatPercentage(kohPurity))% pure)",
                weight: koh, pct: batchPct(koh), isSummary: false
            ))
            rows.append(CalculatedAmountRow(
                label: "NaOH (\(formatPercentage(naohPercentage))%, \(formatPercentage(naohPurity))% pure)",
                weight: naoh, pct: batchPct(naoh), isSummary: false
            ))
        } else {
            rows.append(CalculatedAmountRow(
                label: "\(lyeType) (\(formatPercentage(lyePurity))%, \(formatPercentage(superFat))% SF)",
                weight: totalLye, pct: batchPct(totalLye), isSummary: false
            ))
        }
        rows.append(CalculatedAmountRow(
            label: "Water (\(formatPercentage(waterParts)):1)",
            weight: totalWater, pct: batchPct(totalWater), isSummary: false
        ))
        rows.append(CalculatedAmountRow(label: "Batch total", weight: batchTotal, pct: 100, isSummary: true))
        return rows
    }

    var fragranceTargetPercentage: Double { fragrancePercentage }

    /// Recommended fragrance load shown beside the fragrance section header — but
    /// only when fragrances are entered in an absolute mass unit. For percentage
    /// units (% of oils / batch / liquids) it isn't shown: the user is either
    /// already working in % of oils, or deliberately using a different base.
    var fragranceTarget: FragranceTarget? {
        guard !fragranceDrafts.isEmpty else { return nil }
        let units = Set(fragranceDrafts.map(\.unit))
        guard units.count == 1, let unit = fragranceDrafts.first?.unit,
              MassUnitConverter.isMass(unit) else { return nil }
        guard totalOilBatchWeight > 0 else { return nil }

        let targetInOilUnit = totalOilBatchWeight * fragranceTargetPercentage / 100
        let target = MassUnitConverter.convert(targetInOilUnit, from: displayWeightUnit, to: unit) ?? targetInOilUnit
        let amountText = target.formatted(.number.precision(.fractionLength(0...2)))
        let enteredSum = fragranceDrafts.reduce(0) { $0 + $1.amount }
        return FragranceTarget(
            text: "\(amountText) \(unit) (\(formatPercentage(fragranceTargetPercentage))%)",
            percentage: fragranceTargetPercentage,
            isOverTarget: target > 0 && enteredSum > target * 1.005
        )
    }

    var extraIngredientData: (sectionA: [ExtraSectionARow], sectionB: [ExtraSectionBRow])? {
        guard let calculations = oilAmountCalculations,
              let totalLye = calculatedLyeAmount,
              let totalWater = calculatedWaterAmount else { return nil }

        let oils = calculations.reduce(0.0) { $0 + $1.weight }
        guard oils > 0 else { return nil }

        let batchTotal = oils + totalLye + totalWater

        // Extra lye to neutralise each acid, split by the recipe's lye ratio. A
        // side with no lye (nil multiplier) is omitted so the extras table drops
        // that subrow.
        func triple(_ val1: Double, _ val2: Double, _ val3: Double, factor: Double, multiplier: Double?) -> (v1: Double, v2: Double, v3: Double)? {
            guard let multiplier else { return nil }
            let scale = factor * multiplier
            return (val1 * scale, val2 * scale, val3 * scale)
        }
        func single(_ amount: Double, factor: Double, multiplier: Double?) -> Double? {
            guard let multiplier else { return nil }
            return amount * factor * multiplier
        }

        let citric1 = oils * 0.01
        let citric2 = oils * 0.02
        let citric3 = oils * 0.03
        let sectionA: [ExtraSectionARow] = [
            ExtraSectionARow(label: "Sodium Lactate (60%)", val1: oils * 0.01, val2: oils * 0.02, val3: oils * 0.03),
            ExtraSectionARow(
                label: "Citric Acid Powder",
                val1: citric1, val2: citric2, val3: citric3,
                naohLyeSolution: triple(citric1, citric2, citric3, factor: 0.625, multiplier: naohAcidMultiplier),
                kohLyeSolution: triple(citric1, citric2, citric3, factor: 0.625, multiplier: kohAcidMultiplier)
            ),
        ]

        let ascorbic = oils * 0.01
        let lactic = oils * 0.0075
        let sectionB: [ExtraSectionBRow] = [
            ExtraSectionBRow(label: "EO / Fragrance Oil", minValue: oils * fragranceTargetPercentage / 100),
            ExtraSectionBRow(label: "Ascorbic Acid", minValue: ascorbic,
                naohLyeSolution: single(ascorbic, factor: 0.2020, multiplier: naohAcidMultiplier),
                kohLyeSolution: single(ascorbic, factor: 0.2020, multiplier: kohAcidMultiplier)),
            ExtraSectionBRow(label: "Lactic Acid", minValue: lactic,
                naohLyeSolution: single(lactic, factor: 0.5920, multiplier: naohAcidMultiplier),
                kohLyeSolution: single(lactic, factor: 0.5920, multiplier: kohAcidMultiplier)),
            ExtraSectionBRow(label: "Tetrasodium EDTA", minValue: batchTotal * 0.005),
            ExtraSectionBRow(label: "Sodium Citrate", minValue: oils * 0.013, maxValue: oils * 0.039),
            ExtraSectionBRow(label: "Potassium Citrate", minValue: oils * 0.016, maxValue: oils * 0.048),
            ExtraSectionBRow(label: "Rosemary Oleoresin (ROE)", minValue: oils * 0.0004, maxValue: oils * 0.0005),
        ]

        return (sectionA, sectionB)
    }

    func load(from recipe: Recipe) {
        editingRecipe = recipe
        name = recipe.name
        desc = recipe.desc
        weightUnit = recipe.weightUnit
        totalOilWeight = recipe.totalOilWeight
        oilWeightUnit = recipe.oilWeightUnit
        lyeType = recipe.lyeType
        lyePurity = recipe.lyePurity
        waterParts = recipe.waterParts
        superFat = recipe.superFat
        fragrancePercentage = recipe.fragrancePercentage
        useHybrid = recipe.useHybrid
        kohPercentage = recipe.kohPercentage
        naohPercentage = recipe.naohPercentage
        kohPurity = recipe.kohPurity
        naohPurity = recipe.naohPurity
        lyeIngredient = recipe.lyeIngredient
        kohLyeIngredient = recipe.kohLyeIngredient

        oilDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .oil }
            .map {
                return OilIngredientDraft(ingredient: $0.ingredient, amount: $0.percentage, isLocked: true)
            }
        additiveDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .additive }
            .map { IngredientAmountDraft(ingredient: $0.ingredient, amount: $0.additiveAmount, unit: $0.additiveUnit) }
        fragranceDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .fragrance }
            .map { IngredientAmountDraft(ingredient: $0.ingredient, amount: $0.additiveAmount, unit: $0.additiveUnit) }

        productDrafts = recipe.products.map {
            RecipeProductDraft(size: $0.size, unitSymbol: $0.unitSymbol, modelID: $0.persistentModelID)
        }
        if productDrafts.isEmpty {
            productDrafts = [Self.defaultProductDraft()]
        }
    }

    func addOil(_ ingredient: Ingredient) {
        guard !oilDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        oilDrafts.append(OilIngredientDraft(ingredient: ingredient))
        if weightUnitIsPercentage { redistributePercentages() }
    }

    func removeOil(at offsets: IndexSet) {
        oilDrafts.remove(atOffsets: offsets)
        if weightUnitIsPercentage { redistributePercentages() }
    }

    func userEdited(id: UUID, amount: Double) {
        guard let idx = oilDrafts.firstIndex(where: { $0.id == id }) else { return }
        oilDrafts[idx].amount = amount
        if weightUnitIsPercentage {
            oilDrafts[idx].isLocked = true
            redistributePercentages()
        }
    }

    func addAdditive(_ ingredient: Ingredient) {
        guard !additiveDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        additiveDrafts.append(IngredientAmountDraft(ingredient: ingredient, unit: defaultAdditiveUnit))
    }

    func removeAdditive(at offsets: IndexSet) {
        additiveDrafts.remove(atOffsets: offsets)
    }

    func updateAdditive(id: UUID, amount: Double? = nil, unit: String? = nil) {
        guard let idx = additiveDrafts.firstIndex(where: { $0.id == id }) else { return }
        if let amount { additiveDrafts[idx].amount = amount }
        if let unit { additiveDrafts[idx].unit = unit }
    }

    func addFragrance(_ ingredient: Ingredient) {
        guard !fragranceDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        let unit = fragranceUnitIsPercentageOfOils ? "% of oils" : defaultFragranceUnit
        fragranceDrafts.append(IngredientAmountDraft(ingredient: ingredient, unit: unit))
        if unit == "% of oils" { redistributeFragrancePercentages() }
    }

    func removeFragrance(at offsets: IndexSet) {
        fragranceDrafts.remove(atOffsets: offsets)
        if fragranceUnitIsPercentageOfOils { redistributeFragrancePercentages() }
    }

    private var hasSeeded = false

    /// Pre-fills the form from an inventory selection, routing each ingredient to
    /// the section its category maps to. Lye and uncategorised ingredients are
    /// skipped — they aren't recipe line items. Runs once.
    func applySeed(_ ingredients: [Ingredient]) {
        guard !hasSeeded else { return }
        hasSeeded = true
        for ingredient in ingredients {
            switch ingredient.category?.ingredientRole {
            case .oil: addOil(ingredient)
            case .additive: addAdditive(ingredient)
            case .fragrance: addFragrance(ingredient)
            case nil: continue
            }
        }
    }

    func updateFragrance(id: UUID, amount: Double? = nil, unit: String? = nil) {
        guard let idx = fragranceDrafts.firstIndex(where: { $0.id == id }) else { return }
        if let amount { fragranceDrafts[idx].amount = amount }
        if let unit {
            fragranceDrafts[idx].unit = unit
            fragranceDrafts.indices.forEach { fragranceDrafts[$0].isLocked = false }
            if unit == "% of oils" { redistributeFragrancePercentages() }
        }
    }

    func userEditedFragrance(id: UUID, amount: Double) {
        guard let idx = fragranceDrafts.firstIndex(where: { $0.id == id }) else { return }
        fragranceDrafts[idx].amount = amount
        fragranceDrafts[idx].isLocked = true
        redistributeFragrancePercentages()
    }

    private var fragranceUnitIsPercentageOfOils: Bool {
        fragranceDrafts.first?.unit == "% of oils"
    }

    private func redistributeFragrancePercentages() {
        let target = fragranceTargetPercentage
        let lockedSum = fragranceDrafts.filter(\.isLocked).reduce(0) { $0 + $1.amount }
        let remaining = max(0, target - lockedSum)
        let unlockedIndices = fragranceDrafts.indices.filter { !fragranceDrafts[$0].isLocked }
        guard !unlockedIndices.isEmpty else { return }
        let share = (remaining / Double(unlockedIndices.count) * 10).rounded() / 10
        for (enumIdx, idx) in unlockedIndices.enumerated() {
            if enumIdx == unlockedIndices.count - 1 {
                let assignedSum = unlockedIndices.dropLast().reduce(0.0) { $0 + fragranceDrafts[$1].amount }
                fragranceDrafts[idx].amount = max(0, remaining - assignedSum)
            } else {
                fragranceDrafts[idx].amount = share
            }
        }
    }

    func addProduct(defaultUnitSymbol: String) {
        productDrafts.append(RecipeProductDraft(unitSymbol: defaultUnitSymbol))
    }

    // MARK: - Extra ingredient suggestions

    /// Case-insensitive containment in either direction — the single matching
    /// rule for extras labels and acid factors, so an ingredient the UI offers
    /// as an acid match always gets its lye compensation too.
    private static func namesMatch(_ a: String, _ b: String) -> Bool {
        let a = a.lowercased(), b = b.lowercased()
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a.contains(b) || b.contains(a)
    }

    /// Inventory ingredient matching an extras-table label, by case-insensitive
    /// containment either way ("Citric Acid Powder" ↔ "Citric Acid",
    /// "Sodium Lactate (60%)" ↔ "Sodium Lactate").
    func matchedExtraIngredient(label: String, in inventory: [Ingredient]) -> Ingredient? {
        inventory.first { Self.namesMatch(label, $0.name) }
    }

    /// Whether the ingredient is already among the additive drafts — drives the
    /// checkmark on its extras row, including additives the user added manually.
    func isExtraAdded(_ ingredient: Ingredient) -> Bool {
        additiveDrafts.contains { $0.ingredient.persistentModelID == ingredient.persistentModelID }
    }

    /// Adds the suggested extras amount (already in the batch unit) as a regular
    /// additive draft so cost, products, and batch creation all pick it up — or
    /// removes the ingredient's draft when it is already present.
    func toggleExtra(_ ingredient: Ingredient, amount: Double) {
        if let idx = additiveDrafts.firstIndex(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) {
            additiveDrafts.remove(at: idx)
        } else {
            additiveDrafts.append(IngredientAmountDraft(ingredient: ingredient, amount: amount, unit: displayWeightUnit))
        }
    }

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
        let lye = lyeBatchBreakdown
        let total = (oils + additives + fragrances + lye).reduce(0) { $0 + $1.cost }
        return ProductCostBreakdown(oils: oils, additives: additives, fragrances: fragrances, lye: lye, total: total)
    }

    var batchTotalCost: Double { wholeBatchBreakdown.total }

    var hasIngredients: Bool {
        !oilDrafts.isEmpty || !additiveDrafts.isEmpty || !fragranceDrafts.isEmpty
    }

    // All breakdown amounts are expressed in the batch (oils) unit for display;
    // cost is always derived from the gram-equivalent so it stays correct
    // regardless of the chosen oil weight unit.

    private var oilBatchBreakdown: [IngredientProductBreakdown] {
        guard let calcs = oilAmountCalculations else { return [] }
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

    private var fragranceBatchBreakdown: [IngredientProductBreakdown] {
        breakdown(for: fragranceDrafts)
    }

    /// Breakdown rows for additive/fragrance drafts, with amounts in the batch
    /// (oils) unit and cost derived from the gram-equivalent.
    private func breakdown(for drafts: [IngredientAmountDraft]) -> [IngredientProductBreakdown] {
        drafts.compactMap { draft in
            guard draft.amount > 0,
                  let batchAmount = amountInBatchUnit(
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
            return [row(ingredient, calculatedLyeAmount)].compactMap { $0 }
        }
        return [
            row(lyeIngredient, calculatedNaOHLyeAmount),
            row(kohLyeIngredient, calculatedKOHLyeAmount),
        ].compactMap { $0 }
    }

    /// Total oil weight in the batch (oils) unit.
    private var totalOilBatchWeight: Double {
        oilAmountCalculations?.reduce(0) { $0 + $1.weight } ?? 0
    }

    /// Total batch weight in the batch (oils) unit (fragrances excluded — their
    /// amounts are derived from oils/lye/water percentages, so including them in
    /// the denominator would inflate the batch weight and understate product shares).
    private func batchTotalWeight(from batch: ProductCostBreakdown) -> Double {
        let additives = batch.additives.reduce(0) { $0 + $1.ingredientAmount }
        let lye = calculatedLyeAmount ?? 0
        let water = calculatedWaterAmount ?? 0
        return totalOilBatchWeight + additives + lye + water
    }

    private func scaleBreakdown(_ source: ProductCostBreakdown, by factor: Double) -> ProductCostBreakdown {
        func scale(_ rows: [IngredientProductBreakdown]) -> [IngredientProductBreakdown] {
            rows.map {
                IngredientProductBreakdown(
                    ingredient: $0.ingredient,
                    ingredientAmount: $0.ingredientAmount * factor,
                    cost: $0.cost * factor
                )
            }
        }
        let oils = scale(source.oils)
        let additives = scale(source.additives)
        let fragrances = scale(source.fragrances)
        let lye = scale(source.lye)
        let total = (oils + additives + fragrances + lye).reduce(0) { $0 + $1.cost }
        return ProductCostBreakdown(oils: oils, additives: additives, fragrances: fragrances, lye: lye, total: total)
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
        if usesEnteredUnit, let unit = enteredUnit(for: row.ingredient),
           let result = IngredientUnitConverter.convert(
               row.ingredientAmount, from: displayWeightUnit, to: unit, density: row.ingredient.density
           ) {
            let note: String?
            if let density = result.density {
                note = conversionNote(
                    amount: result.value, unit: unit,
                    equivalent: row.ingredientAmount, equivalentUnit: displayWeightUnit,
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
            amount: amount, unit: unit,
            equivalent: result.value, equivalentUnit: ingredient.unit,
            density: density, usedDefaultDensity: result.usedDefaultDensity
        )
    }

    /// Explains the volume↔mass crossing behind a breakdown row — the displayed
    /// amount, its equivalent on the other side of the crossing, and the density
    /// used — for the row's info popover.
    private func conversionNote(
        amount: Double, unit: String,
        equivalent: Double, equivalentUnit: String,
        density: Double, usedDefaultDensity: Bool
    ) -> String {
        let amountText = amount.formatted(.number.precision(.fractionLength(0...2)))
        let equivalentText = equivalent.formatted(.number.precision(.fractionLength(0...2)))
        let densityText = density.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
        if usedDefaultDensity {
            return "\(amountText) \(unit) ≈ \(equivalentText) \(equivalentUnit), converted using the default density of \(densityText) g/ml. Set a density on the ingredient for a more accurate conversion."
        }
        return "\(amountText) \(unit) ≈ \(equivalentText) \(equivalentUnit), converted using the ingredient's density of \(densityText) g/ml."
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
        switch unit {
        case "% of oils":
            return totalOilBatchWeight > 0 ? totalOilBatchWeight * fraction : nil
        case "% of batch":
            guard let lye = calculatedLyeAmount, let water = calculatedWaterAmount else { return nil }
            return (totalOilBatchWeight + lye + water) * fraction
        case "% of liquids":
            guard let lye = calculatedLyeAmount, let water = calculatedWaterAmount else { return nil }
            return (lye + water) * fraction
        default: return nil
        }
    }

    func resolveDefaultLyeIngredient(from inventory: [Ingredient]) {
        let candidates = inventory.filter { $0.category?.name == IngredientCategory.Name.lyes }
        guard !candidates.isEmpty else { return }

        func match(_ name: String) -> Ingredient? {
            candidates.first { $0.name.lowercased().contains(name) }
        }

        if lyeIngredient == nil {
            // Single lye is currently always NaOH; the hybrid path's NaOH portion
            // shares this ingredient.
            lyeIngredient = match("sodium hydroxide") ?? candidates.first
        }
        if kohLyeIngredient == nil {
            kohLyeIngredient = match("potassium hydroxide") ?? candidates.first
        }
    }

    private func weightedCostPerUnit(for ingredient: Ingredient) -> Double {
        let purchases = ingredient.purchases.filter { $0.quantity > 0 }
        guard !purchases.isEmpty else { return 0 }
        let totalCost = purchases.reduce(0.0) { $0 + $1.totalPrice }
        let totalQty = purchases.reduce(0.0) { $0 + $1.quantity }
        return totalQty > 0 ? totalCost / totalQty : 0
    }

    private func redistributePercentages() {
        let lockedSum = oilDrafts.filter(\.isLocked).reduce(0) { $0 + $1.amount }
        let remaining = max(0, 100 - lockedSum)
        let unlockedIndices = oilDrafts.indices.filter { !oilDrafts[$0].isLocked }
        guard !unlockedIndices.isEmpty else { return }
        let share = (remaining / Double(unlockedIndices.count) * 10).rounded() / 10
        for (enumIdx, idx) in unlockedIndices.enumerated() {
            if enumIdx == unlockedIndices.count - 1 {
                let assignedSum = unlockedIndices.dropLast().reduce(0.0) { $0 + oilDrafts[$1].amount }
                oilDrafts[idx].amount = max(0, remaining - assignedSum)
            } else {
                oilDrafts[idx].amount = share
            }
        }
    }

    private static let percentageFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .autoupdatingCurrent
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    func formatPercentage(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return Self.percentageFormatter.string(from: NSNumber(value: rounded)) ?? "0"
    }

    @discardableResult
    func save(context: ModelContext) -> Recipe {
        let recipe: Recipe
        if let existing = editingRecipe {
            recipe = existing
        } else {
            recipe = Recipe(name: "", desc: "")
            context.insert(recipe)
        }
        recipe.name = name.trimmingCharacters(in: .whitespaces)
        recipe.desc = desc.trimmingCharacters(in: .whitespaces)
        recipe.weightUnit = weightUnit
        recipe.totalOilWeight = totalOilWeight
        recipe.oilWeightUnit = oilWeightUnit
        recipe.lyeType = lyeType
        recipe.lyePurity = lyePurity
        recipe.waterParts = waterParts
        recipe.superFat = superFat
        recipe.fragrancePercentage = fragrancePercentage
        recipe.useHybrid = useHybrid
        recipe.kohPercentage = kohPercentage
        recipe.naohPercentage = naohPercentage
        recipe.kohPurity = kohPurity
        recipe.naohPurity = naohPurity
        recipe.lyeIngredient = lyeIngredient
        recipe.kohLyeIngredient = kohLyeIngredient

        recipe.ingredients.forEach { context.delete($0) }

        for draft in oilDrafts {
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: draft.amount, role: .oil)
            ri.recipe = recipe
            context.insert(ri)
        }
        for draft in additiveDrafts {
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: 0, role: .additive)
            ri.additiveAmount = draft.amount
            ri.additiveUnit = draft.unit
            ri.recipe = recipe
            context.insert(ri)
        }
        for draft in fragranceDrafts {
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: 0, role: .fragrance)
            ri.additiveAmount = draft.amount
            ri.additiveUnit = draft.unit
            ri.recipe = recipe
            context.insert(ri)
        }

        recipe.products.forEach { context.delete($0) }
        for draft in productDrafts {
            let rp = RecipeProduct(size: draft.size, unitSymbol: draft.unitSymbol)
            rp.recipe = recipe
            context.insert(rp)
        }
        return recipe
    }
}
