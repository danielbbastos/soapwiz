import OSLog
import SwiftUI
import SwiftData

/// What a batch needs of one ingredient, already converted into that
/// ingredient's inventory unit and weighed against what's in stock.
struct BatchRequirement: Identifiable {
    let id: PersistentIdentifier
    let ingredient: Ingredient
    /// Amount needed, in the ingredient's inventory unit.
    let required: Double
    /// Amount currently in stock across all purchases, in the same unit.
    let available: Double
    let unit: String

    var isShort: Bool { available + 1e-9 < required }
    var shortfall: Double { max(0, required - available) }
}

/// Drives creating a `Batch` from a recipe: computes how much of each ingredient
/// is needed (reusing the SW-71 cost/consumption engine for the per-ingredient
/// amounts), checks stock, and on confirmation deducts inventory FIFO and
/// records an immutable snapshot. With `tracksInventory` off, stock is neither
/// checked nor deducted and the snapshot records amounts without any cost.
@Observable
@MainActor
final class BatchProductionViewModel {
    private static let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "batch")

    var batchCount: Int = 1

    /// The code the batch will be labelled with. Starts as `suggestedCode` and
    /// is the user's to change, to anything no other batch carries; left empty,
    /// `create(context:)` generates one.
    var code: String = ""

    /// What the code would be if the user left it alone — shown as the field's
    /// placeholder once they clear it.
    private(set) var suggestedCode: String = ""

    let tracksInventory: Bool

    /// How the bars are being made. Only asked of a recipe that cures, and
    /// moves the suggested cure: a hot-process bar is ready sooner.
    var process: SoapProcess = .cold

    /// What the cure would be for the current `process`, or `nil` when the
    /// recipe isn't a solid bar — the batch then never mentions a cure.
    var cureEstimate: CureEstimate? {
        CureEstimator.estimate(
            makesSoap: engine.makesSoap,
            soapType: engine.soapType,
            fattyAcidProfile: fattyAcidProfile,
            process: process
        )
    }

    /// The cure the batch will be made with: the estimate's longer end until
    /// the user picks a length of their own, which then stays put when the
    /// process changes. Zero when the recipe doesn't cure.
    var cureDays: Int {
        get {
            guard let estimate = cureEstimate else { return 0 }
            return chosenCureDays ?? estimate.defaultDays
        }
        set { chosenCureDays = newValue }
    }

    private var chosenCureDays: Int?

    /// The batch this model made, once it has. The sheet stays on screen while
    /// it closes, by which time the batch is in the store carrying the very
    /// code the field shows — it must not be mistaken for a clash, nor prompt
    /// a fresh suggestion.
    private var createdBatch: Batch?

    private let recipe: Recipe
    private let engine: RecipeFormViewModel
    /// The recipe's blend, read once: the recipe can't change while the sheet
    /// is up, and the estimate is asked for on every render.
    private let fattyAcidProfile: FattyAcidProfile

    init(
        recipe: Recipe,
        lyeCandidates: [Ingredient],
        neutralizerCandidates: [Ingredient] = [],
        tracksInventory: Bool = true
    ) {
        self.recipe = recipe
        self.tracksInventory = tracksInventory
        let engine = RecipeFormViewModel()
        engine.load(from: recipe)
        engine.resolveDefaultLyeIngredient(from: lyeCandidates)
        engine.resolveDefaultNeutralizerIngredient(from: neutralizerCandidates)
        self.engine = engine
        self.fattyAcidProfile = RecipeStats(oilDrafts: engine.oilDrafts, makesSoap: engine.makesSoap).fattyAcidProfile
    }

    /// Per-ingredient requirements for the current `batchCount`, in each
    /// ingredient's inventory unit.
    var requirements: [BatchRequirement] {
        let breakdown = engine.wholeBatchBreakdown
        let rows = breakdown.oils + breakdown.additives + breakdown.fragrances + breakdown.lye

        // An ingredient can appear in more than one category (e.g. an oil also
        // used as an additive); sum its display-unit amounts before converting.
        var displayAmounts: [PersistentIdentifier: (ingredient: Ingredient, amount: Double)] = [:]
        for row in rows where row.ingredientAmount > 0 {
            let id = row.ingredient.persistentModelID
            displayAmounts[id, default: (row.ingredient, 0)].amount += row.ingredientAmount
        }

        let count = Double(max(1, batchCount))
        let displayUnit = engine.displayWeightUnit

        return displayAmounts.values.compactMap { entry in
            let ingredient = entry.ingredient
            let neededInDisplayUnit = entry.amount * count
            // Convert the recipe-unit amount into the ingredient's inventory unit.
            // Mass↔mass and volume↔mass (density) both flow through the shared
            // converter; if the units aren't convertible, take the amount as-is.
            let required = IngredientUnitConverter
                .convert(neededInDisplayUnit, from: displayUnit, to: ingredient.unit, density: ingredient.density)?
                .value ?? neededInDisplayUnit
            guard required > 0 else { return nil }
            return BatchRequirement(
                id: ingredient.persistentModelID,
                ingredient: ingredient,
                required: required,
                available: ingredient.totalRemaining,
                unit: ingredient.unit
            )
        }
        .sorted { $0.ingredient.name < $1.ingredient.name }
    }

    /// Requirements that can't be fully satisfied from stock. Always empty when
    /// inventory isn't tracked, since nothing is drawn from stock.
    var shortages: [BatchRequirement] {
        shortages(in: requirements)
    }

    /// `shortages` for requirements the caller already computed, so a view that
    /// shows both doesn't rebuild the breakdown twice per render.
    func shortages(in requirements: [BatchRequirement]) -> [BatchRequirement] {
        guard tracksInventory else { return [] }
        return requirements.filter(\.isShort)
    }

    /// Total mass the current `batchCount` will produce, in `batchWeightUnit`:
    /// oils + lye + water + additives + fragrances. Deliberately not a sum of
    /// `BatchRequirement.required` — those are per-ingredient inventory units
    /// (grams for one, millilitres for another) and adding them is meaningless.
    var totalBatchWeight: Double {
        engine.batchTotalWeight * Double(max(1, batchCount))
    }

    /// The unit `totalBatchWeight` is expressed in — the recipe's oil weight unit.
    var batchWeightUnit: String { engine.displayWeightUnit }

    var canCreate: Bool {
        let reqs = requirements
        return !reqs.isEmpty && shortages(in: reqs).isEmpty
    }

    /// What the current `batchCount` would cost, computed from the same FIFO
    /// plan `create(context:)` applies — the preview always matches the charge.
    /// Inventory is not touched.
    var estimatedCost: Double {
        guard tracksInventory else { return 0 }
        return requirements.reduce(0) { total, req in
            total + plannedDraws(for: req).reduce(0) { $0 + $1.drawn * $1.purchase.pricePerUnit }
        }
    }

    /// Works out the code this batch would take given the codes already in use,
    /// and puts it in `code` unless the user has typed one of their own. Called
    /// again when the batches change, so a code that arrives by sync while the
    /// sheet is open moves the suggestion on instead of colliding with it.
    func suggestCode(existingCodes: [String], date: Date = .now) {
        guard createdBatch == nil else { return }
        let suggestion = BatchCodeGenerator.suggestedCode(
            recipeName: recipe.name,
            date: date,
            existingCodes: existingCodes
        )
        if code.isEmpty || code == suggestedCode {
            code = suggestion
        }
        suggestedCode = suggestion
    }

    /// Whether another batch already carries the code as typed. A taken code
    /// blocks creation: two batches under one code can't be told apart on a
    /// label.
    func codeIsTaken(among batches: [Batch]) -> Bool {
        BatchCodeGenerator.isTaken(code, among: batches, excluding: createdBatch)
    }

    /// Deducts inventory FIFO and persists an immutable `Batch` snapshot. Returns
    /// `nil` without mutating anything when stock is insufficient, when the
    /// code typed belongs to another batch, or when the existing batches can't
    /// be read to check — all before any purchase is touched.
    @discardableResult
    func create(context: ModelContext, date: Date = .now) -> Batch? {
        let reqs = requirements
        guard !reqs.isEmpty, shortages(in: reqs).isEmpty else { return nil }

        // Read before the batch is inserted, so these are only the batches its
        // code could clash with — including one this model made earlier. A
        // failed read must not pass for "no batches": the code would go
        // unchecked, and a generated one would start again at 01.
        let existing: [Batch]
        do {
            existing = try context.fetch(FetchDescriptor<Batch>())
        } catch {
            Self.log.error("Couldn't read the existing batches, so none was created: \(error, privacy: .public)")
            return nil
        }
        guard !BatchCodeGenerator.isTaken(code, among: existing) else { return nil }

        let batch = Batch(
            recipe: recipe,
            code: resolvedCode(among: existing, date: date),
            recipeName: recipe.name,
            dateCreated: date,
            batchCount: max(1, batchCount),
            tracksInventory: tracksInventory,
            cureDays: cureDays,
            process: cureEstimate == nil ? "" : process.rawValue,
            cureBand: cureEstimate?.band.rawValue ?? ""
        )
        context.insert(batch)

        var total = 0.0
        for req in reqs {
            let lineItem = deduct(req, batch: batch, context: context)
            total += lineItem.cost
        }
        batch.totalCost = total
        createdBatch = batch
        return batch
    }

    /// The code as typed, or a generated one when the field was left empty —
    /// every batch leaves here with a code.
    private func resolvedCode(among existing: [Batch], date: Date) -> String {
        let typed = BatchCodeGenerator.trimmed(code)
        guard typed.isEmpty else { return typed }
        return BatchCodeGenerator.suggestedCode(
            recipeName: recipe.name,
            date: date,
            existingCodes: existing.map(\.code)
        )
    }

    /// FIFO plan for draining `req` from its ingredient's purchases oldest
    /// first: which purchases to draw from and how much. Pure — inventory is
    /// only mutated when `deduct` applies the plan.
    private func plannedDraws(for req: BatchRequirement) -> [(purchase: IngredientPurchase, drawn: Double)] {
        let purchases = req.ingredient.purchases.sorted { $0.dateOfPurchase < $1.dateOfPurchase }
        var remaining = req.required
        var plan: [(purchase: IngredientPurchase, drawn: Double)] = []

        for purchase in purchases where remaining > 1e-9 {
            guard purchase.remainingAmount > 0 else { continue }
            let drawn = min(remaining, purchase.remainingAmount)
            remaining -= drawn
            plan.append((purchase, drawn))
        }
        return plan
    }

    /// Drains `req` from its ingredient's purchases oldest first, building the
    /// snapshot line item and decrementing `remainingAmount` as it goes. Every
    /// purchase the plan touches is marked opened, not just the first.
    private func deduct(_ req: BatchRequirement, batch: Batch, context: ModelContext) -> BatchLineItem {
        var draws: [BatchPurchaseDraw] = []
        var cost = 0.0

        for (purchase, drawn) in tracksInventory ? plannedDraws(for: req) : [] {
            purchase.remainingAmount -= drawn
            purchase.markOpened()
            let drawCost = drawn * purchase.pricePerUnit
            cost += drawCost
            draws.append(BatchPurchaseDraw(
                purchaseUUID: purchase.uuid,
                purchaseBadge: purchase.badge,
                amountDrawn: drawn,
                pricePerUnit: purchase.pricePerUnit,
                cost: drawCost
            ))
        }

        let lineItem = BatchLineItem(
            ingredient: req.ingredient,
            ingredientName: req.ingredient.name,
            amountConsumed: req.required,
            unit: req.unit,
            cost: cost,
            draws: draws
        )
        lineItem.batch = batch
        context.insert(lineItem)
        return lineItem
    }
}
