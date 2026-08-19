import SwiftUI
import SwiftData

@Observable
final class RecipeFormViewModel {
    var name: String = ""
    var desc: String = ""

    /// The recipe's photo at display size. `PhotoField` downscales whatever the
    /// user picks before it lands here, and `save` derives the thumbnail from
    /// it — nothing else needs to know the difference between the two copies.
    var imageData: Data?
    var weightUnit: String = "%" {
        didSet {
            guard weightUnit != oldValue else { return }
            reconcileAdditiveUnits()
        }
    }

    /// What the recipe makes. Drives every saponification-specific field and
    /// section: a general recipe hides them rather than disabling them, and
    /// leaves their stored values untouched so switching back is lossless.
    var recipeKind: RecipeKind = .soap {
        didSet {
            guard recipeKind != oldValue else { return }
            reconcileAdditiveUnits()
        }
    }
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

    /// Themes this recipe is filed under. Kept in `sortedByName` order so the
    /// dirty check compares two stable lists rather than two arbitrary ones.
    var selectedCollections: [RecipeCollection] = []

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

    /// The Config tab's "Non-soap product" toggle. A toggle rather than a
    /// two-value picker because soap is the ordinary case and the alternative is
    /// the deliberate one; the kind itself stays an enum so a third one can be
    /// added without reshaping the model.
    var isNonSoapProduct: Bool {
        get { recipeKind == .general }
        set { recipeKind = newValue ? .general : .soap }
    }

    /// Whether the recipe saponifies, and so whether the lye maths, the soap
    /// method options, and the soap-property stats apply to it at all.
    var makesSoap: Bool { recipeKind == .soap }

    /// What the base weight is called. A soap recipe's percentages resolve
    /// against its oils; a general recipe's resolve against a plain total.
    var baseWeightLabel: String { makesSoap ? "Total oil weight" : "Total weight" }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// What the Ingredients section's running total shows. On a non-soap recipe
    /// the base rows and the percentage additives share one 100% scale, so both
    /// count toward it; a soap recipe keeps additives on top of an oil total
    /// that is already 100%, which is the soap-making convention.
    var totalPercentage: Double {
        oilDrafts.reduce(0) { $0 + $1.amount } + (makesSoap ? 0 : percentageAdditiveTotal)
    }

    /// Sum of the additive rows entered as a share of the total. Only these
    /// participate in the 100% scale — a gram or a count doesn't.
    var percentageAdditiveTotal: Double {
        additiveDrafts
            .filter { $0.unit == RecipeUnitOptions.percentOfTotal }
            .reduce(0) { $0 + $1.amount }
    }

    var totalPercentageText: String { formatPercentage(totalPercentage) }

    var displayWeightUnit: String {
        weightUnitIsPercentage ? oilWeightUnit : weightUnit
    }

    /// Default unit for a mass row.
    ///
    /// On a soap recipe additives are conventionally entered as a weight, so
    /// they default to grams in percentage mode (rather than "% of oils") to
    /// avoid silently applying a percentage of the oils. A non-soap recipe in
    /// percentage mode defaults to the shared "% of total" scale instead, so a
    /// formula reads as one set of percentages rather than a mix of percentages
    /// and weights.
    var defaultAdditiveUnit: String {
        guard weightUnitIsPercentage else { return weightUnit }
        return makesSoap ? "g" : RecipeUnitOptions.percentOfTotal
    }

    /// The unit a row takes for this ingredient.
    ///
    /// On a non-soap recipe this is the whole story — units are derived, never
    /// chosen, so a formula reads in one unit throughout. An ingredient stocked
    /// by the piece is a component rather than part of the mixture and stays a
    /// count in either kind: no percentage of a wick means anything.
    func derivedUnit(for ingredient: Ingredient) -> String {
        ingredient.unit == RecipeUnitOptions.count ? RecipeUnitOptions.count : defaultAdditiveUnit
    }

    /// How a row's unit reads in the ingredients list. A non-soap recipe has one
    /// percentage scale, so "% of total" is shown as plain "%" — the same thing
    /// the base rows show, which is what makes the merged section read as one
    /// list. The stored value keeps its longer name, which is what distinguishes
    /// it from soap's "% of oils".
    func unitLabel(for unit: String) -> String {
        unit == RecipeUnitOptions.percentOfTotal ? "%" : unit
    }

    /// Rewrites the units the current kind can't express, leaving the rest alone.
    ///
    /// A non-soap recipe has exactly one mass unit — whatever the Config tab
    /// declared — so anything else becomes it. A soap recipe can't express
    /// "% of total", so only that is rewritten; its own "% of oils", grams and
    /// millilitres are deliberate choices and survive a round trip through the
    /// other kind. Counts are never touched.
    func normalizeAdditiveUnits() { reconcileAdditiveUnits() }

    private func reconcileAdditiveUnits() {
        for index in additiveDrafts.indices {
            let unit = additiveDrafts[index].unit
            guard !RecipeUnitOptions.isCount(unit) else { continue }
            if makesSoap {
                if unit == RecipeUnitOptions.percentOfTotal {
                    additiveDrafts[index].unit = defaultAdditiveUnit
                }
            } else if unit != defaultAdditiveUnit {
                additiveDrafts[index].unit = defaultAdditiveUnit
            }
        }
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
            cfmNeutralizer: cfmNeutralizer,
            producesLye: makesSoap
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
    /// The calculated-amounts table. A soap recipe's comes from the lye
    /// calculator; a non-soap recipe's is built from the resolved cost
    /// breakdown, which is the only place additive and fragrance units have
    /// already been turned into weights.
    var calculatedAmountRows: [CalculatedAmountRow]? {
        makesSoap ? lyeCalculator.calculatedAmountRows : generalCalculatedAmountRows
    }

    /// Every line item at its resolved weight, then the batch total — which is
    /// the total the Config tab declared, since the percentages now share one
    /// 100% scale.
    ///
    /// Count rows are left out: this table is weights in a single unit, and a
    /// jar has none. They stay visible in the cost breakdown, priced in `un`.
    private var generalCalculatedAmountRows: [CalculatedAmountRow]? {
        let batch = wholeBatchBreakdown
        let weighed = (batch.oils + batch.additives + batch.fragrances)
            .filter { !$0.isCountBased && $0.ingredientAmount > 0 }
        guard !weighed.isEmpty else { return nil }

        let total = weighed.reduce(0.0) { $0 + $1.ingredientAmount }
        var rows = weighed.map { row in
            CalculatedAmountRow(
                label: row.ingredient.name,
                weight: row.ingredientAmount,
                pct: total > 0 ? row.ingredientAmount / total * 100 : 0,
                isSummary: false
            )
        }
        rows.append(CalculatedAmountRow(label: "Batch total", weight: total, pct: 100, isSummary: true))
        return rows
    }

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

    /// Adds an ingredient to whichever section its category maps to. Used by the
    /// non-soap form, whose single Ingredients list spans both roles: the user
    /// picks from one list and the recipe still files each row correctly, so the
    /// roles survive a switch back to soap. A fragrance picked here is routed
    /// too rather than dropped, since the picker's role filter is advisory.
    func addIngredient(_ ingredient: Ingredient) {
        switch ingredient.category?.ingredientRole {
        case .oil: addOil(ingredient)
        case .fragrance: addFragrance(ingredient)
        case .additive, nil: addAdditive(ingredient)
        }
    }

    func addAdditive(_ ingredient: Ingredient) {
        guard !additiveDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        additiveDrafts.append(
            IngredientAmountDraft(ingredient: ingredient, unit: derivedUnit(for: ingredient))
        )
        rebalanceForSharedPercentageScale()
    }

    func removeAdditive(at offsets: IndexSet) {
        additiveDrafts.remove(atOffsets: offsets)
        rebalanceForSharedPercentageScale()
    }

    func updateAdditive(id: UUID, amount: Double? = nil, unit: String? = nil) {
        guard let idx = additiveDrafts.firstIndex(where: { $0.id == id }) else { return }
        if let amount { additiveDrafts[idx].amount = amount }
        if let unit { additiveDrafts[idx].unit = unit }
        rebalanceForSharedPercentageScale()
    }

    /// Re-runs the base-row redistribution after an additive changed, so the one
    /// 100% scale a non-soap recipe uses stays at 100. A soap recipe's additives
    /// sit outside the oil total, so nothing needs rebalancing there.
    private func rebalanceForSharedPercentageScale() {
        guard !makesSoap, weightUnitIsPercentage else { return }
        redistributePercentages()
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

    // MARK: - Collections

    func isSelected(_ collection: RecipeCollection) -> Bool {
        selectedCollections.contains { $0 === collection }
    }

    func toggleCollection(_ collection: RecipeCollection) {
        if let index = selectedCollections.firstIndex(where: { $0 === collection }) {
            selectedCollections.remove(at: index)
        } else {
            selectedCollections = (selectedCollections + [collection]).sortedByName
        }
    }

    /// What the picker row shows on the right. Spelled out for a single
    /// collection, counted beyond that — a row of names would overflow the
    /// narrow side of the form long before it stayed readable.
    var collectionsLabel: String {
        switch selectedCollections.count {
        case 0: "None"
        case 1: selectedCollections[0].name
        default: "\(selectedCollections.count) selected"
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

    /// Shares the remainder of the 100% scale across the unlocked base rows.
    ///
    /// On a non-soap recipe the percentage additives are claimants on the same
    /// 100 as the base rows, so they count against the remainder exactly like a
    /// locked base row: setting an additive to 1% pulls the base rows down to
    /// 99% between them rather than pushing the formula to 101%.
    private func redistributePercentages() {
        let lockedOils = oilDrafts.filter(\.isLocked).reduce(0) { $0 + $1.amount }
        let lockedSum = lockedOils + (makesSoap ? 0 : percentageAdditiveTotal)
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
