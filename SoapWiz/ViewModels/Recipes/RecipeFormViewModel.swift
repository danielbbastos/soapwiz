import SwiftUI
import SwiftData

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

    /// The recipe-wide unit every fragrance row is entered in. Mutate through
    /// `setFragranceUnit(_:)` (or `load`, which reconciles stored rows), so
    /// every draft's `unit` string stays in sync — the calculator and
    /// persistence read the drafts, not this property.
    var fragranceUnit: FragranceUnit = .percentOfOils

    /// Whether the unit was chosen deliberately (picker, load, import) rather
    /// than still holding its initial value. Until then, the first fragrance
    /// added adopts `defaultFragranceUnit` for the recipe's weight mode.
    @ObservationIgnored
    var fragranceUnitExplicitlySet = false
    var useHybrid: Bool = false
    var kohPercentage: Double = 90
    var naohPercentage: Double = 10
    var kohPurity: Double = 90
    var naohPurity: Double = 99
    var isCreamSoap: Bool = false
    var useCFM: Bool = false
    var cfmNeutralizer: CFMNeutralizer = .boricAcid
    var lyeIngredient: Ingredient?
    var kohLyeIngredient: Ingredient?

    /// Line items whose ingredient could not be resolved. With CloudKit
    /// mirroring on, a `RecipeIngredient` can arrive before the `Ingredient` it
    /// points at, so these rows are surfaced and preserved rather than dropped.
    var unresolvedLineItemCount: Int = 0

    @ObservationIgnored
    var editingRecipe: Recipe?

    /// The form's state the last time it matched what is stored. `nil` until the
    /// form finishes loading. Read and written by `RecipeFormViewModel+DirtyState`.
    @ObservationIgnored
    var snapshot: RecipeFormSnapshot?

    /// Guards `applyImport` the way `hasSeeded` guards `applySeed`: the form's
    /// `.task` can run again, and a second application would double every row.
    @ObservationIgnored
    var hasImported = false

    init() {
        productDrafts = [.seededPlaceholder()]
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

    /// Default fragrance unit: percentage-of-oils when the recipe is measured in
    /// percentages, otherwise the recipe's weight unit (grams when that unit
    /// isn't one fragrances can be entered in).
    var defaultFragranceUnit: FragranceUnit {
        weightUnitIsPercentage ? .percentOfOils : FragranceUnit(rawValue: weightUnit) ?? .grams
    }

    /// Default unit for new additive rows. Additives are conventionally entered
    /// as a weight, so they default to grams in percentage mode (rather than
    /// "% of oils") to avoid silently applying a percentage of the oils.
    var defaultAdditiveUnit: String {
        weightUnitIsPercentage ? "g" : weightUnit
    }

    // MARK: - Calculators

    /// Lye/water computation, rebuilt from current state on each access.
    var lyeCalculator: LyeCalculator {
        LyeCalculator(
            oilDrafts: oilDrafts,
            additiveDrafts: additiveDrafts,
            useHybrid: useHybrid,
            lyeType: lyeType,
            lyePurity: lyePurity,
            naohPercentage: naohPercentage,
            kohPercentage: kohPercentage,
            naohPurity: naohPurity,
            kohPurity: kohPurity,
            superFat: superFat,
            waterParts: waterParts,
            weightUnitIsPercentage: weightUnitIsPercentage,
            totalOilWeight: totalOilWeight,
            displayWeightUnit: displayWeightUnit,
            useCFM: useCFM,
            cfmNeutralizer: cfmNeutralizer
        )
    }

    private var costCalculator: RecipeCostCalculator {
        RecipeCostCalculator(
            lye: lyeCalculator,
            additiveDrafts: additiveDrafts,
            fragranceDrafts: fragranceDrafts,
            fragranceUnit: fragranceUnit,
            fragrancePercentage: fragrancePercentage,
            displayWeightUnit: displayWeightUnit,
            lyeIngredient: lyeIngredient,
            kohLyeIngredient: kohLyeIngredient
        )
    }

    // MARK: - Lye / amounts (delegated to LyeCalculator)

    var oilAmountCalculations: [OilAmountCalculation]? { lyeCalculator.oilAmountCalculations }
    var calculatedNaOHLyeAmount: Double? { lyeCalculator.calculatedNaOHLyeAmount }
    var calculatedKOHLyeAmount: Double? { lyeCalculator.calculatedKOHLyeAmount }
    var calculatedLyeAmount: Double? { lyeCalculator.calculatedLyeAmount }
    var calculatedWaterAmount: Double? { lyeCalculator.calculatedWaterAmount }
    var calculatedAmountRows: [CalculatedAmountRow]? { lyeCalculator.calculatedAmountRows }

    var soapType: SoapType {
        SoapType.classify(
            useHybrid: useHybrid,
            naohPercentage: naohPercentage,
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

    // MARK: - Fragrance target

    var fragranceTargetPercentage: Double { fragrancePercentage }

    /// Recommended fragrance load shown beside the fragrance section header. For
    /// absolute mass units it is the target the entered weights should reach;
    /// for `% of fragrances` it is the resolved load the blend shares are scaled
    /// to, so it can never be exceeded. For the other percentage units
    /// (% of oils / batch / liquids) it isn't shown: the user is either already
    /// working in % of oils, or deliberately using a different base.
    var fragranceTarget: FragranceTarget? {
        guard !fragranceDrafts.isEmpty else { return nil }
        let totalOilBatchWeight = lyeCalculator.totalOilBatchWeight
        guard totalOilBatchWeight > 0 else { return nil }
        let targetInOilUnit = totalOilBatchWeight * fragranceTargetPercentage / 100

        if fragranceUnit == .percentOfFragrances {
            let amountText = targetInOilUnit.formatted(.number.precision(.fractionLength(0...2)))
            return FragranceTarget(
                text: "\(amountText) \(displayWeightUnit) (\(formatPercentage(fragranceTargetPercentage))%)",
                percentage: fragranceTargetPercentage,
                isOverTarget: false
            )
        }
        let unit = fragranceUnit.rawValue
        guard MassUnitConverter.isMass(unit) else { return nil }
        let target = MassUnitConverter.convert(targetInOilUnit, from: displayWeightUnit, to: unit) ?? targetInOilUnit
        let amountText = target.formatted(.number.precision(.fractionLength(0...2)))
        let enteredSum = fragranceDrafts.reduce(0) { $0 + $1.amount }
        return FragranceTarget(
            text: "\(amountText) \(unit) (\(formatPercentage(fragranceTargetPercentage))%)",
            percentage: fragranceTargetPercentage,
            isOverTarget: target > 0 && enteredSum > target * 1.005
        )
    }

    /// Sum of the blend shares, non-nil only in `% of fragrances` mode. Drives
    /// the warning shown when the shares don't add up to 100%.
    var fragranceBlendTotal: Double? {
        guard fragranceUnit == .percentOfFragrances, !fragranceDrafts.isEmpty else { return nil }
        return fragranceDrafts.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Cost / breakdown (delegated to RecipeCostCalculator)

    func breakdownAndCost(for product: RecipeProductDraft, batch: ProductCostBreakdown) -> ProductCostBreakdown {
        costCalculator.breakdownAndCost(for: product, batch: batch)
    }

    func breakdownAndCost(for product: RecipeProductDraft) -> ProductCostBreakdown {
        costCalculator.breakdownAndCost(for: product)
    }

    var wholeBatchBreakdown: ProductCostBreakdown { costCalculator.wholeBatchBreakdown }

    var batchTotalCost: Double { wholeBatchBreakdown.total }

    /// Total mass of one whole batch in the batch (oils) unit — everything that
    /// goes in the pot. Doubles as the denominator for a fixed-size product's
    /// share of the batch, so the weight shown when making a batch and the
    /// weight cost is allocated against are the same number.
    var batchTotalWeight: Double { costCalculator.batchTotalWeight(from: wholeBatchBreakdown) }

    var hasIngredients: Bool {
        !oilDrafts.isEmpty || !additiveDrafts.isEmpty || !fragranceDrafts.isEmpty
    }

    func displayedAmount(for row: IngredientProductBreakdown, usesEnteredUnit: Bool) -> BreakdownAmountDisplay {
        costCalculator.displayedAmount(for: row, usesEnteredUnit: usesEnteredUnit)
    }

    // MARK: - Mutation

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
        if fragranceDrafts.isEmpty && !fragranceUnitExplicitlySet {
            fragranceUnit = defaultFragranceUnit
        }
        fragranceDrafts.append(IngredientAmountDraft(ingredient: ingredient, unit: fragranceUnit.rawValue))
        redistributeFragrancePercentages()
    }

    func removeFragrance(at offsets: IndexSet) {
        fragranceDrafts.remove(atOffsets: offsets)
        redistributeFragrancePercentages()
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

    /// Switches the recipe-wide fragrance unit, stamping every draft and
    /// clearing the locks the old basis accumulated. Entering `% of fragrances`
    /// re-expresses the current amounts as shares of their own sum, preserving
    /// the blend the user already built; entering `% of oils` redistributes the
    /// target load evenly; the absolute units keep the entered numbers.
    func setFragranceUnit(_ unit: FragranceUnit) {
        fragranceUnitExplicitlySet = true
        guard unit != fragranceUnit else { return }
        fragranceUnit = unit
        for idx in fragranceDrafts.indices {
            fragranceDrafts[idx].unit = unit.rawValue
            fragranceDrafts[idx].isLocked = false
        }
        switch unit {
        case .percentOfFragrances:
            normalizeFragranceShares()
        case .percentOfOils:
            redistributeFragrancePercentages()
        case .grams, .ounces, .milliliters, .percentOfBatch, .percentOfLiquids:
            break
        }
    }

    func userEditedFragrance(id: UUID, amount: Double) {
        guard let idx = fragranceDrafts.firstIndex(where: { $0.id == id }) else { return }
        fragranceDrafts[idx].amount = amount
        guard redistributionTotal != nil else { return }
        fragranceDrafts[idx].isLocked = true
        redistributeFragrancePercentages()
    }

    /// Collapses loaded rows onto `unit` — recipes saved before the unit became
    /// recipe-wide can hold rows that disagree. Rows already in that unit keep
    /// their amounts (locked when the unit spreads a budget), mismatched rows
    /// are unlocked and re-derived by one redistribution. No-op when the rows
    /// already agree, so loading a clean recipe never rewrites amounts.
    func reconcileLoadedFragranceRows(with unit: FragranceUnit) {
        fragranceUnitExplicitlySet = true
        fragranceUnit = unit
        guard fragranceDrafts.contains(where: { $0.unit != unit.rawValue }) else { return }
        let redistributes = redistributionTotal != nil
        for idx in fragranceDrafts.indices {
            fragranceDrafts[idx].isLocked = redistributes && fragranceDrafts[idx].unit == unit.rawValue
            fragranceDrafts[idx].unit = unit.rawValue
        }
        if redistributes { redistributeFragrancePercentages() }
    }

    /// The total the fragrance rows should sum to in the units that spread a
    /// budget across the rows — the recipe's fragrance load for `% of oils`,
    /// 100 for shares of the blend — and `nil` for the units that don't.
    private var redistributionTotal: Double? {
        switch fragranceUnit {
        case .percentOfOils: fragranceTargetPercentage
        case .percentOfFragrances: 100
        case .grams, .ounces, .milliliters, .percentOfBatch, .percentOfLiquids: nil
        }
    }

    /// Re-expresses the current amounts as shares of their own sum totalling
    /// 100 (18 g / 12 g → 60 / 40), falling back to an even split when there is
    /// nothing to preserve.
    private func normalizeFragranceShares() {
        let sum = fragranceDrafts.reduce(0) { $0 + $1.amount }
        guard sum > 0 else {
            redistributeFragrancePercentages()
            return
        }
        for idx in fragranceDrafts.indices.dropLast() {
            fragranceDrafts[idx].amount = (fragranceDrafts[idx].amount / sum * 1000).rounded() / 10
        }
        if let last = fragranceDrafts.indices.last {
            let assigned = fragranceDrafts.dropLast().reduce(0) { $0 + $1.amount }
            fragranceDrafts[last].amount = max(0, 100 - assigned)
        }
    }

    private func redistributeFragrancePercentages() {
        guard let target = redistributionTotal else { return }
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

    func resolveDefaultLyeIngredient(from inventory: [Ingredient]) {
        let candidates = inventory.filter { $0.category?.name == IngredientCategory.Name.lyes }
        guard !candidates.isEmpty else { return }

        func match(_ name: String) -> Ingredient? {
            candidates.first { $0.name.lowercased().contains(name) }
        }

        // Resolving only ever fills a blank, so the baseline moves with it — a
        // lye ingredient arriving late from CloudKit isn't a user edit.
        if lyeIngredient == nil {
            // Single lye is currently always NaOH; the hybrid path's NaOH portion
            // shares this ingredient.
            lyeIngredient = match("sodium hydroxide") ?? candidates.first
            snapshot?.lyeIngredient = lyeIngredient
        }
        if kohLyeIngredient == nil {
            kohLyeIngredient = match("potassium hydroxide") ?? candidates.first
            snapshot?.kohLyeIngredient = kohLyeIngredient
        }
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

    func formatPercentage(_ value: Double) -> String {
        PercentageFormatter.string(value)
    }
}
