import Foundation

/// Checks a model-extracted draft against the text the model read.
///
/// Greedy generation makes the model consistent, not correct. On device it has
/// invented amounts for a shopping list with none, taken the superfat from the
/// lye weight, and listed sodium hydroxide as an oil. Each of those reaches the
/// lye calculation, so each is corrected here deterministically, whatever the
/// model returned.
///
/// The direction is always towards less: a row is dropped, an amount becomes 0,
/// a setting is cleared. The review screen then shows a gap for the user to
/// fill rather than a number nobody wrote.
enum RecipeImportDraftChecker {
    static func checked(_ draft: RecipeImportDraft, against text: String) -> RecipeImportDraft {
        var checked = draft
        let numbers = RecipeTextNumbers.values(in: text)

        let lyeTypeFromRows = (checked.oils + checked.additives + checked.fragrances)
            .lazy
            .compactMap { ImportedIngredientName.lyeType(ofLye: $0.name) }
            .first

        checked.oils = ingredients(checked.oils, numbers: numbers)
        checked.additives = ingredients(checked.additives, numbers: numbers)
        checked.fragrances = ingredients(checked.fragrances, numbers: numbers)
        // After amounts are checked: a header the model gave an invented amount
        // only reads as a header once that amount is gone.
        checked = checked.droppingSectionHeaders()
        checked.batchSize = checked.batchSize.flatMap { RecipeTextNumbers.contains($0, in: numbers) ? $0 : nil }
        // After the batch size check: a batch size read from the oil weights is
        // their sum, which the text need not write anywhere.
        checked = statedPercentageRecipe(checked, in: text) ?? matchingOilUnits(checked)

        let stated = RecipeTextSettingsParser.parse(text)
        checked.superFat = stated.superFat ?? valueNear(
            checked.superFat, keyword: RecipeTextSettingsParser.superFatKeyword, in: text, requiringPercent: false
        )
        // No fallback for the water ratio: a number beside "water" or "lye" is
        // nearly always a weight, and "4.5 oz lye" read as 4.5 parts water is
        // still inside the plausible range.
        checked.waterParts = stated.waterParts
        checked.fragrancePercentage = stated.fragrancePercentage ?? valueNear(
            checked.fragrancePercentage, keyword: RecipeTextSettingsParser.fragranceKeyword, in: text, requiringPercent: true
        )
        checked.lyeType = stated.lyeType ?? checked.lyeType ?? lyeTypeFromRows

        let neutralizer = failorNeutralizer(for: checked, statedInText: stated.cfmNeutralizer)
        checked.cfmNeutralizer = neutralizer
        if let neutralizer {
            // Only the chosen neutraliser's own rows are pulled out. A recipe
            // that named a second, different one — borax alongside boric acid —
            // keeps it as an ordinary additive rather than losing it silently.
            func isChosenNeutralizer(_ row: ImportedIngredient) -> Bool {
                ImportedIngredientName.failorNeutralizer(named: row.name) == neutralizer
            }
            checked.oils.removeAll(where: isChosenNeutralizer)
            checked.additives.removeAll(where: isChosenNeutralizer)
            checked.fragrances.removeAll(where: isChosenNeutralizer)
        }
        return checked
    }

    /// The Catherine Failor neutraliser this import uses, or `nil`.
    ///
    /// The method neutralises the deliberate excess lye of a non-solid soap, so
    /// it is read only into a KOH recipe — the only non-solid an import can
    /// express, since a draft has no dual-lye (cream) form. In a solid bar — a
    /// NaOH recipe, or one that names no lye and so defaults to one — borax and
    /// boric acid are ordinary additives and their rows stay. A neutraliser
    /// named in a row is trusted over one merely inferred from a method mention
    /// in the text.
    private static func failorNeutralizer(
        for draft: RecipeImportDraft,
        statedInText: CFMNeutralizer?
    ) -> CFMNeutralizer? {
        guard draft.lyeType == "KOH" else { return nil }
        let fromRows = (draft.oils + draft.additives + draft.fragrances)
            .lazy
            .compactMap { ImportedIngredientName.failorNeutralizer(named: $0.name) }
            .first
        return fromRows ?? statedInText
    }

    /// The model's value for a setting the parser didn't find, kept only when
    /// the text writes that number beside the setting's keyword.
    private static func valueNear(
        _ value: Double?,
        keyword: some RegexComponent,
        in text: String,
        requiringPercent: Bool
    ) -> Double? {
        value.flatMap {
            RecipeTextSettingsParser.appears($0, near: keyword, in: text, requiringPercent: requiringPercent) ? $0 : nil
        }
    }

    private static func ingredients(_ ingredients: [ImportedIngredient], numbers: [Double]) -> [ImportedIngredient] {
        ingredients.compactMap { ingredient in
            guard !ImportedIngredientName.isLye(ingredient.name),
                  !ImportedIngredientName.isWater(ingredient.name),
                  !ImportedIngredientName.isSetting(ingredient.name) else { return nil }
            guard ingredient.amount != 0, !RecipeTextNumbers.contains(ingredient.amount, in: numbers) else {
                return ingredient
            }
            var unstated = ingredient
            unstated.amount = 0
            return unstated
        }
    }
}
