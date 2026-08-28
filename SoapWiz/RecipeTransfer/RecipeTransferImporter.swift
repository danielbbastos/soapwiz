import Foundation
import SwiftData

/// Writes a reviewed payload into the store.
///
/// The exact path saves straight to the library rather than opening the recipe
/// form. The form's "nothing is saved until you press Save" exists to catch a
/// misread percentage on the language-model path; an exact payload has nothing
/// to proofread, and it is the only behaviour that scales to fifteen recipes
/// arriving at once. The review screen is the confirmation.
@MainActor
enum RecipeTransferImporter {

    /// Applies the plan and returns the recipes created, in payload order.
    ///
    /// Everything is inserted into the context but nothing is saved: the caller
    /// owns the save, so a failure part-way leaves a context it can roll back
    /// rather than a library holding half an import.
    @discardableResult
    static func apply(_ plan: RecipeTransferPlan, into context: ModelContext, categories: [IngredientCategory]) -> [Recipe] {
        let resolved = resolveIngredients(plan, into: context, categories: categories)
        return plan.recipeSummaries.map { summary in
            recipe(from: summary, plan: plan, ingredients: resolved, into: context)
        }
    }

    // MARK: - Ingredients

    /// Every pooled ingredient as a live model: the one already in the
    /// inventory, or a new one carrying the sender's chemistry.
    ///
    /// A created ingredient takes the payload's saponification values, density
    /// and fatty-acid profile because a recipe cannot be calculated without
    /// them and `IngredientFormView` has no fields for the last two. A *matched*
    /// one is left exactly as it is: the recipient's own chemistry is the
    /// authority on their own shelf, and overwriting it would let a shared
    /// recipe silently rewrite the lye weight of every other recipe using that
    /// oil.
    private static func resolveIngredients(
        _ plan: RecipeTransferPlan,
        into context: ModelContext,
        categories: [IngredientCategory]
    ) -> [Ingredient] {
        let categoryIndex = Dictionary(
            categories.map { ($0.name.lookupKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return plan.ingredients.map { entry in
            if let existing = entry.existing { return existing }

            let ingredient = Ingredient(
                name: entry.incoming.name,
                category: categoryIndex[entry.suggestedCategoryName.lookupKey],
                unit: entry.incoming.unit
            )
            ingredient.sapValue = entry.incoming.sapValue
            ingredient.kohSapValue = entry.incoming.kohSapValue
            ingredient.density = entry.incoming.density
            ingredient.fattyAcidProfile = entry.incoming.fattyAcidProfile
            context.insert(ingredient)
            return ingredient
        }
    }

    // MARK: - Recipe

    private static func recipe(
        from summary: RecipeTransferRecipeSummary,
        plan: RecipeTransferPlan,
        ingredients: [Ingredient],
        into context: ModelContext
    ) -> Recipe {
        let incoming = summary.recipe
        // The plan's name, not the payload's: it has already been checked
        // against the library and suffixed if it collided, and the review
        // screen has already told the user that is what will happen.
        let recipe = Recipe(name: summary.resolvedName, desc: incoming.desc)
        context.insert(recipe)

        recipe.recipeKind = incoming.recipeKind
        recipe.weightUnit = incoming.weightUnit
        recipe.totalOilWeight = incoming.totalOilWeight
        recipe.oilWeightUnit = incoming.oilWeightUnit
        recipe.lyeType = incoming.lyeType
        recipe.lyePurity = incoming.lyePurity
        recipe.waterParts = incoming.waterParts
        recipe.superFat = incoming.superFat
        recipe.useHybrid = incoming.useHybrid
        recipe.kohPercentage = incoming.kohPercentage
        recipe.naohPercentage = incoming.naohPercentage
        recipe.kohPurity = incoming.kohPurity
        recipe.naohPurity = incoming.naohPurity
        recipe.isCreamSoap = incoming.isCreamSoap
        recipe.useCFM = incoming.useCFM
        recipe.cfmNeutralizer = incoming.cfmNeutralizer
        recipe.fragrancePercentage = incoming.fragrancePercentage
        recipe.fragranceUnit = incoming.fragranceUnit

        // Only the names this library already knows. Unmatched ones are dropped
        // rather than created — see `RecipeTransferPlan`.
        recipe.collections = incoming.collectionNames.compactMap { plan.matchedCollections[$0] }

        for line in incoming.ingredients {
            let item = RecipeIngredient(
                ingredient: ingredients[line.ingredientIndex],
                percentage: line.percentage,
                role: RecipeIngredientRole(rawValue: line.role) ?? .oil
            )
            item.additiveAmount = line.additiveAmount
            item.additiveUnit = line.additiveUnit
            item.recipe = recipe
            context.insert(item)
        }

        for product in incoming.products {
            let item = RecipeProduct(size: product.size, unitSymbol: product.unitSymbol)
            item.recipe = recipe
            context.insert(item)
        }

        return recipe
    }
}
