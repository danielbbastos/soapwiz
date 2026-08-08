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
    ///
    /// A new recipe starts on shares of the blend: it is the one unit that
    /// reads the same whether the recipe is written in percentages or in
    /// weights, since the absolute load comes from `fragrancePercentage`
    /// either way. `Recipe.fragranceUnit`'s schema default is deliberately
    /// different — a recipe stored before the unit became recipe-wide has to
    /// come back as "% of oils".
    var fragranceUnit: FragranceUnit = .percentOfFragrances
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
