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
    var useHybrid: Bool = false
    var kohPercentage: Double = 90
    var naohPercentage: Double = 10
    var kohPurity: Double = 90
    var naohPurity: Double = 99
    var lyeIngredient: Ingredient?
    var kohLyeIngredient: Ingredient?

    @ObservationIgnored
    var editingRecipe: Recipe?

    init() {
        productDrafts = [Self.defaultProductDraft()]
    }

    static func defaultProductDraft() -> RecipeProductDraft {
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

    // MARK: - Calculators

    /// Lye/water computation, rebuilt from current state on each access.
    private var lyeCalculator: LyeCalculator {
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
            displayWeightUnit: displayWeightUnit
        )
    }

    private var costCalculator: RecipeCostCalculator {
        RecipeCostCalculator(
            lye: lyeCalculator,
            additiveDrafts: additiveDrafts,
            fragranceDrafts: fragranceDrafts,
            displayWeightUnit: displayWeightUnit,
            lyeIngredient: lyeIngredient,
            kohLyeIngredient: kohLyeIngredient
        )
    }

    private var extrasBuilder: RecipeExtrasBuilder {
        RecipeExtrasBuilder(lye: lyeCalculator, fragranceTargetPercentage: fragranceTargetPercentage)
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

    /// Recommended fragrance load shown beside the fragrance section header — but
    /// only when fragrances are entered in an absolute mass unit. For percentage
    /// units (% of oils / batch / liquids) it isn't shown: the user is either
    /// already working in % of oils, or deliberately using a different base.
    var fragranceTarget: FragranceTarget? {
        guard !fragranceDrafts.isEmpty else { return nil }
        let units = Set(fragranceDrafts.map(\.unit))
        guard units.count == 1, let unit = fragranceDrafts.first?.unit,
              MassUnitConverter.isMass(unit) else { return nil }
        let totalOilBatchWeight = lyeCalculator.totalOilBatchWeight
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

    // MARK: - Extra ingredient suggestions

    var extraIngredientData: (sectionA: [ExtraSectionARow], sectionB: [ExtraSectionBRow])? {
        extrasBuilder.extraIngredientData
    }

    /// Inventory ingredient matching an extras-table label, by case-insensitive
    /// containment either way ("Citric Acid Powder" ↔ "Citric Acid",
    /// "Sodium Lactate (60%)" ↔ "Sodium Lactate").
    func matchedExtraIngredient(label: String, in inventory: [Ingredient]) -> Ingredient? {
        inventory.first { ingredientNamesMatch(label, $0.name) }
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

    // MARK: - Cost / breakdown (delegated to RecipeCostCalculator)

    func breakdownAndCost(for product: RecipeProductDraft, batch: ProductCostBreakdown) -> ProductCostBreakdown {
        costCalculator.breakdownAndCost(for: product, batch: batch)
    }

    func breakdownAndCost(for product: RecipeProductDraft) -> ProductCostBreakdown {
        costCalculator.breakdownAndCost(for: product)
    }

    var wholeBatchBreakdown: ProductCostBreakdown { costCalculator.wholeBatchBreakdown }

    var batchTotalCost: Double { wholeBatchBreakdown.total }

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
