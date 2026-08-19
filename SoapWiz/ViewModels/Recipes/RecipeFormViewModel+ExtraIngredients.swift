import Foundation
import SwiftData

/// The extras table — suggested additions (citric acid, sodium lactate, cream-soap
/// water and glycerine) and the inventory matching that lets a suggestion be
/// toggled straight into the recipe's additives.
extension RecipeFormViewModel {
    private var extrasBuilder: RecipeExtrasBuilder {
        RecipeExtrasBuilder(
            lye: lyeCalculator,
            fragranceTargetPercentage: fragranceTargetPercentage,
            // A recipe switched to non-soap keeps its stored cream-soap flag so
            // switching back is lossless, so the kind has to veto it here.
            isCreamSoap: makesSoap && isCreamSoap
        )
    }

    var extraIngredientData: (sectionA: [ExtraSectionARow], sectionB: [ExtraSectionBRow])? {
        extrasBuilder.extraIngredientData
    }

    /// Cream-soap recommended additions (extra water, glycerine), or `nil` when
    /// cream soap is off. Shown above the standard extras table.
    var creamSoapAdditions: [ExtraSectionBRow]? {
        extrasBuilder.creamSoapAdditions
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
}
