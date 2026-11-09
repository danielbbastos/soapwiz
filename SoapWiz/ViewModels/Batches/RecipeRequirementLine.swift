import Foundation
import SwiftData

/// What a recipe needs of one ingredient, in that ingredient's inventory unit,
/// before any stock is weighed against it. The one place a recipe's breakdown
/// becomes per-ingredient requirements, shared by Create Batch and by
/// `RecipeCoverage` so the two can never disagree.
struct RecipeRequirementLine: Identifiable {
    let id: PersistentIdentifier
    let ingredient: Ingredient
    let required: Double
    let unit: String

    /// The working copy a recipe is read through, set up exactly as the batch
    /// sheet sets it up so every caller resolves the same lye and neutraliser.
    static func makeEngine(
        for recipe: Recipe,
        lyeCandidates: [Ingredient],
        neutralizerCandidates: [Ingredient]
    ) -> RecipeFormViewModel {
        let engine = RecipeFormViewModel()
        engine.load(from: recipe)
        engine.resolveDefaultLyeIngredient(from: lyeCandidates)
        engine.resolveDefaultNeutralizerIngredient(from: neutralizerCandidates)
        return engine
    }

    /// Requirements for `batchCount` batches of what `engine` holds, sorted by
    /// ingredient name.
    static func lines(for engine: RecipeFormViewModel, batchCount: Int) -> [RecipeRequirementLine] {
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
            return RecipeRequirementLine(
                id: ingredient.persistentModelID,
                ingredient: ingredient,
                required: required,
                unit: ingredient.unit
            )
        }
        .sorted { $0.ingredient.name < $1.ingredient.name }
    }
}
