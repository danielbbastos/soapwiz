import Foundation
import SwiftData

/// The extras table — suggested additions (citric acid, sodium lactate, and
/// cream-soap glycerine) and the inventory matching that lets a suggestion be
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

        // Any manual toggle of the cream-soap glycerine hands ownership to the
        // user, so switching the method off no longer treats it as an auto-add to
        // silently remove — even when they re-added it at the suggested amount.
        if ingredientNamesMatch(LyeCalculator.creamSoapGlycerineLabel, ingredient.name) {
            autoAddedGlycerineAmount = nil
            creamSoapGlycerinePending = false
        }
    }

    /// Toggles the cream-soap method. Beyond the flag, turning it on drops the
    /// recommended glycerine straight into the additives so it is costed and
    /// deducted — when the inventory has a glycerine to attach it to and the
    /// recipe already has oils to size the dose; otherwise the add waits (see
    /// `reconcileCreamSoapGlycerine`). The extra dilution water rides along in
    /// the calculated amounts either way. Turning the method off takes that same
    /// glycerine row back out, but only while the user hasn't changed its amount
    /// — an edit makes it theirs to keep.
    func setCreamSoap(_ isOn: Bool, from inventory: [Ingredient]) {
        guard isOn != isCreamSoap else { return }
        isCreamSoap = isOn

        if isOn {
            creamSoapGlycerinePending = true
            reconcileCreamSoapGlycerine(from: inventory)
        } else {
            creamSoapGlycerinePending = false
            if let auto = autoAddedGlycerineAmount,
               let glycerine = matchedExtraIngredient(label: LyeCalculator.creamSoapGlycerineLabel, in: inventory),
               let idx = additiveDrafts.firstIndex(where: {
                   $0.ingredient.persistentModelID == glycerine.persistentModelID && $0.amount == auto
               }) {
                additiveDrafts.remove(at: idx)
            }
            autoAddedGlycerineAmount = nil
        }
    }

    /// Completes a pending cream-soap glycerine add once it's actually possible —
    /// the inventory has a glycerine to cost it against and the recipe has oils to
    /// size the dose. Called both from `setCreamSoap` and whenever oils change, so
    /// toggling the method on before adding oils still lands the glycerine. Runs
    /// only while `creamSoapGlycerinePending`, so a glycerine the user has since
    /// removed is never silently re-added.
    func reconcileCreamSoapGlycerine(from inventory: [Ingredient]) {
        guard isCreamSoap, creamSoapGlycerinePending,
              let glycerine = matchedExtraIngredient(
                  label: LyeCalculator.creamSoapGlycerineLabel, in: inventory
              )
        else { return }

        // Already in the additives (the user's own, or a hand-added one): the
        // intent is satisfied, and it isn't ours to auto-remove later.
        guard !isExtraAdded(glycerine) else {
            creamSoapGlycerinePending = false
            autoAddedGlycerineAmount = nil
            return
        }

        let oils = lyeCalculator.totalOilBatchWeight
        guard oils > 0 else { return } // no oils yet — stay pending and retry

        let amount = oils * LyeCalculator.creamSoapGlycerineFraction
        additiveDrafts.append(IngredientAmountDraft(ingredient: glycerine, amount: amount, unit: displayWeightUnit))
        autoAddedGlycerineAmount = amount
        creamSoapGlycerinePending = false
    }
}
