import Foundation

/// Tracking whether the form holds work that leaving it would lose. The baseline
/// lives in `snapshot` on the view model itself, since an extension can't hold
/// storage; everything that reads or moves it is here.
extension RecipeFormViewModel {
    private var currentSnapshot: RecipeFormSnapshot {
        RecipeFormSnapshot(
            name: name, desc: desc, imageData: imageData,
            weightUnit: weightUnit, recipeKind: recipeKind, totalOilWeight: totalOilWeight,
            oilWeightUnit: oilWeightUnit, lyeType: lyeType, lyePurity: lyePurity,
            waterParts: waterParts, superFat: superFat, oilDrafts: oilDrafts,
            additiveDrafts: additiveDrafts, fragranceDrafts: fragranceDrafts,
            productDrafts: productDrafts, fragrancePercentage: fragrancePercentage,
            fragranceUnit: fragranceUnit,
            useHybrid: useHybrid, kohPercentage: kohPercentage, naohPercentage: naohPercentage,
            kohPurity: kohPurity, naohPurity: naohPurity, isCreamSoap: isCreamSoap,
            useCFM: useCFM, cfmNeutralizer: cfmNeutralizer, lyeIngredient: lyeIngredient,
            kohLyeIngredient: kohLyeIngredient, neutralizerIngredient: neutralizerIngredient,
            selectedCollections: selectedCollections
        )
    }

    /// Records the current state as the clean baseline. Called once the form has
    /// loaded, so only what the user does afterwards counts as an edit.
    func captureSnapshot() {
        snapshot = currentSnapshot
    }

    /// Whether leaving the form now would lose work. `false` until a baseline is
    /// captured, so a form that never loaded never blocks its own dismissal.
    var isDirty: Bool {
        guard let snapshot else { return false }
        return snapshot != currentSnapshot
    }

    /// Whether anything that feeds the percentage total has changed since the
    /// form loaded: the rows, the measurement unit, or the recipe kind, which
    /// decides whether percentage additives count. `true` without a baseline,
    /// so a form that never loaded is held to the rule rather than excused.
    var percentageScaleChangedSinceLoad: Bool {
        guard let snapshot else { return true }
        return snapshot.oilDrafts != oilDrafts
            || snapshot.additiveDrafts != additiveDrafts
            || snapshot.weightUnit != weightUnit
            || snapshot.recipeKind != recipeKind
    }
}
