import Foundation

/// One ingredient line as it was written in the source text: a name and an
/// amount, nothing more. The name is a string the user typed or a website
/// printed — it is not yet an `Ingredient`, and resolving it is a separate,
/// user-confirmed step.
struct ImportedIngredient: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var amount: Double
    /// The unit as written, when the source gave one. `nil` in percentage
    /// recipes, where the amount is a share of the oils.
    var unit: String?

    static func == (lhs: ImportedIngredient, rhs: ImportedIngredient) -> Bool {
        lhs.id == rhs.id
    }
}

/// A recipe extracted from free text, holding structure and proportions only.
///
/// This type deliberately has no `sapValue`, `kohSapValue`, `density` or
/// `fattyAcidProfile`, and it never will. Those feed `LyeCalculator`, and a
/// wrong saponification value produces a wrong lye weight — caustic soap is a
/// burn risk, not a data-quality nit. A language model asked for the SAP value
/// of an obscure oil will produce a plausible number whether or not it knows
/// one, and nothing downstream would reveal that it was invented.
///
/// Chemistry reaches a recipe from exactly two places, both of which put a
/// human in the loop: an `Ingredient` the user already has, or the values they
/// enter themselves in `IngredientFormView`.
struct RecipeImportDraft: Equatable {
    var name: String = ""
    var desc: String = ""
    var oils: [ImportedIngredient] = []
    var additives: [ImportedIngredient] = []
    var fragrances: [ImportedIngredient] = []

    /// Whether the oil amounts are shares of the total oils rather than
    /// absolute weights. Determines which of the two weight modes the recipe
    /// form is put into — see `RecipeFormViewModel.weightUnitIsPercentage`.
    var amountsArePercentages: Bool = true

    /// Total oil weight, meaningful only in percentage mode. `nil` when the
    /// source didn't state a batch size.
    var batchSize: Double?

    /// The unit `batchSize` is expressed in, and the unit absolute amounts are
    /// expressed in. One of `RecipeImportDraft.supportedWeightUnits`.
    var batchUnit: String?

    /// The lye the source names, or `nil` when it names none.
    ///
    /// Optional rather than defaulted, because "NaOH" is a claim about the
    /// recipe and a default would put that claim on screen for text that never
    /// mentioned lye — a candle, a balm, a salve. The recipe form still starts
    /// on NaOH; the difference is that the review screen no longer reports it
    /// as something the source said.
    var lyeType: String?
    var superFat: Double?
    var waterParts: Double?
    var fragrancePercentage: Double?

    /// Whether the source said anything about saponifying at all.
    ///
    /// The extraction schema has no notion of a recipe kind, so this is the
    /// closest the text path can get to "is this soap?": a recipe that names no
    /// lye, no superfat and no water ratio is one the review screen should not
    /// be describing in those terms.
    var statesLyeSettings: Bool {
        lyeType != nil || superFat != nil || waterParts != nil
    }

    /// Weight units the recipe form offers, mirroring `weightUnits` in
    /// `RecipeFormView`. Anything else an import produces is discarded rather
    /// than silently reinterpreted.
    static let supportedWeightUnits = ["g", "kg", "oz", "lb"]

    var hasAnyIngredient: Bool {
        !oils.isEmpty || !additives.isEmpty || !fragrances.isEmpty
    }

    /// The unit to measure the recipe in, falling back to grams when the source
    /// gave a unit the form can't offer.
    var resolvedBatchUnit: String {
        guard let batchUnit, Self.supportedWeightUnits.contains(batchUnit) else { return "g" }
        return batchUnit
    }
}
