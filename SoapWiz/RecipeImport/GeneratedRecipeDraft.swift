import Foundation
import FoundationModels

/// One ingredient line the model is allowed to report: a name and an amount.
///
/// There is no field here for a saponification value, a density or a fatty-acid
/// profile, and that omission is the safety mechanism. Guided generation
/// constrains the model's output to this schema, so it cannot return chemistry
/// even if asked to — the numbers that drive the lye calculation can only come
/// from the user's own inventory.
@available(iOS 26, macOS 26, *)
@Generable(description: "One ingredient in a soap recipe")
struct GeneratedIngredient {
    @Guide(description: "The ingredient's name exactly as the source writes it, with no added words")
    var name: String

    @Guide(description: "The number beside the ingredient. Use 0 when the source gives no amount")
    var amount: Double

    @Guide(description: "The unit written beside the amount, such as g, oz or %. Empty when the source gives none")
    var unit: String
}

/// The structure the on-device model extracts from pasted recipe text.
///
/// Mirrors `RecipeImportDraft`, which is the plain type the rest of the app
/// works with. Keeping them separate means the review screen, the ingredient
/// reconciliation and every test involving them compile and run without
/// `FoundationModels` — the framework only exists behind iOS 26 and only runs
/// where Apple Intelligence does.
@available(iOS 26, macOS 26, *)
@Generable(description: "A soap recipe: which oils, in what proportion, and the lye settings")
struct GeneratedRecipeDraft {
    @Guide(description: "The recipe's name. Use an empty string when the source doesn't name it")
    var name: String

    /// No minimum. A floor of one would make the schema demand an oil from text
    /// that has none, and the model can only satisfy that by inventing one —
    /// the opposite of "Report only what the text states". It would also leave
    /// `hasAnyIngredient` permanently true, so the extractor's
    /// `.nothingRecognised` guard could never fire and a page of unrelated text
    /// would arrive at the review screen as a plausible-looking recipe.
    @Guide(description: "Every oil, fat, butter and wax in the recipe, with the amount exactly as written. Leave empty when the text states none", .maximumCount(20))
    var oils: [GeneratedIngredient]

    @Guide(description: "Additives such as clay, sodium lactate, salt, sugar or honey", .maximumCount(12))
    var additives: [GeneratedIngredient]

    @Guide(description: "Fragrance oils and essential oils", .maximumCount(8))
    var fragrances: [GeneratedIngredient]

    @Guide(description: "True when the oil amounts are percentages of the total oils, false when they are weights")
    var amountsArePercentages: Bool

    @Guide(description: "The combined weight of all the oils, when the source states one")
    var batchSize: Double?

    @Guide(description: "The weight unit the source measures in", .anyOf(["g", "kg", "oz", "lb"]))
    var batchUnit: String?

    @Guide(description: "The lye: NaOH for bar soap, KOH for liquid or cream soap", .anyOf(["NaOH", "KOH"]))
    var lyeType: String

    @Guide(description: "Superfat, also called lye discount, as a percentage", .range(0.0...20.0))
    var superFat: Double?

    @Guide(description: "Parts of water per part of lye. A 2:1 water to lye ratio is 2", .range(0.5...5.0))
    var waterParts: Double?

    @Guide(description: "Fragrance load as a percentage of the oil weight", .range(0.0...15.0))
    var fragrancePercentage: Double?
}

@available(iOS 26, macOS 26, *)
extension GeneratedRecipeDraft {
    /// Crosses out of `FoundationModels` into the plain draft the app works
    /// with, discarding anything the recipe form couldn't represent.
    func asImportDraft() -> RecipeImportDraft {
        RecipeImportDraft(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            desc: "",
            oils: oils.map { $0.asImportedIngredient() },
            additives: additives.map { $0.asImportedIngredient() },
            fragrances: fragrances.map { $0.asImportedIngredient() },
            amountsArePercentages: amountsArePercentages,
            batchSize: batchSize.flatMap { $0 > 0 ? $0 : nil },
            batchUnit: batchUnit.flatMap { RecipeImportDraft.supportedWeightUnits.contains($0) ? $0 : nil },
            lyeType: lyeType == "KOH" ? "KOH" : "NaOH",
            superFat: superFat,
            waterParts: waterParts,
            fragrancePercentage: fragrancePercentage
        )
    }
}

@available(iOS 26, macOS 26, *)
extension GeneratedIngredient {
    func asImportedIngredient() -> ImportedIngredient {
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return ImportedIngredient(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            unit: unit.isEmpty ? nil : unit
        )
    }
}
