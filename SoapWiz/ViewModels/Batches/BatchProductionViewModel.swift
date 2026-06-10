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
/// records an immutable snapshot.
@Observable
@MainActor
final class BatchProductionViewModel {
    var batchCount: Int = 1

    private let recipe: Recipe
    private let engine: RecipeFormViewModel

    init(recipe: Recipe, lyeCandidates: [Ingredient]) {
        self.recipe = recipe
        let engine = RecipeFormViewModel()
        engine.load(from: recipe)
        engine.resolveDefaultLyeIngredient(from: lyeCandidates)
        self.engine = engine
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

    /// Requirements that can't be fully satisfied from stock.
    var shortages: [BatchRequirement] {
        requirements.filter(\.isShort)
    }

    var canCreate: Bool {
        !requirements.isEmpty && shortages.isEmpty
    }

    /// What the current `batchCount` would cost, computed from the same FIFO
    /// plan `create(context:)` applies — the preview always matches the charge.
    /// Inventory is not touched.
    var estimatedCost: Double {
        requirements.reduce(0) { total, req in
            total + plannedDraws(for: req).reduce(0) { $0 + $1.drawn * $1.purchase.pricePerUnit }
        }
    }

    /// Deducts inventory FIFO and persists an immutable `Batch` snapshot. Returns
    /// `nil` without mutating anything when stock is insufficient — the stock
    /// check across every ingredient happens before any purchase is touched.
    @discardableResult
    func create(context: ModelContext) -> Batch? {
        let reqs = requirements
        guard !reqs.isEmpty, reqs.allSatisfy({ !$0.isShort }) else { return nil }

        let batch = Batch(recipe: recipe, recipeName: recipe.name, batchCount: max(1, batchCount))
        context.insert(batch)

        var total = 0.0
        for req in reqs {
            let lineItem = deduct(req, batch: batch, context: context)
            total += lineItem.cost
        }
        batch.totalCost = total
        return batch
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
    /// snapshot line item and decrementing `remainingAmount` as it goes.
    private func deduct(_ req: BatchRequirement, batch: Batch, context: ModelContext) -> BatchLineItem {
        var draws: [BatchPurchaseDraw] = []
        var cost = 0.0

        for (purchase, drawn) in plannedDraws(for: req) {
            purchase.remainingAmount -= drawn
            let drawCost = drawn * purchase.pricePerUnit
            cost += drawCost
            draws.append(BatchPurchaseDraw(
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
