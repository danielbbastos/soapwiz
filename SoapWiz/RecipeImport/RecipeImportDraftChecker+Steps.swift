import Foundation

private typealias Checker = RecipeImportDraftChecker

extension RecipeImportDraftChecker {
    /// What every step reads besides the draft, worked out once from the model's
    /// draft and the text before any step runs.
    struct Context {
        let text: String
        let numbers: [Double]
        let stated: RecipeTextSettings
        /// The lye named in a row, found before the rows are filtered: the
        /// lye rows are dropped from the draft by `keepingStatedAmounts`.
        let lyeTypeFromRows: String?

        init(draft: RecipeImportDraft, text: String) {
            self.text = text
            numbers = RecipeTextNumbers.values(in: text)
            stated = RecipeTextSettingsParser.parse(text)
            lyeTypeFromRows = (draft.oils + draft.additives + draft.fragrances)
                .lazy
                .compactMap { ImportedIngredientName.lyeType(ofLye: $0.name) }
                .first
        }
    }

    /// One correction the checker makes, in the order they run.
    enum Step: CaseIterable {
        /// Drops lye, water and setting rows, and zeroes amounts the text never writes.
        case keepingStatedAmounts
        /// Files each row under the section its name or unit shows. Runs before
        /// the oil sums that the batch size and percentage checks read.
        case movingMisplacedRows
        /// Lists each row once. After the move, so a repeat in the wrong section is found.
        case removingDuplicates
        /// Drops rows that are headers. After amounts are checked: a header the
        /// model gave an invented amount only reads as a header once that amount is gone.
        case droppingSectionHeaders
        /// Clears a batch size the text never writes. Before the oil amounts
        /// step, which may set a batch size summed from the oil weights.
        case checkingBatchSize
        /// Reads the oil amounts and unit: a table's columns, else stated shares
        /// and weights, else the units beside the oils. A table's headers say
        /// which number is which, so they come before the single-line scan.
        case readingOilAmounts
        /// Reads weights that are really shares as percentages. Reads the unit
        /// and flag settled by the oil amounts step.
        case readingSharesAsPercentages
        /// Clears a batch size that isn't the oils' total. Reads the unit and
        /// flag settled by the steps above.
        case clearingStaleBatchSize
        /// Takes the superfat the text states, else the model's if the text writes it near the keyword.
        case settingSuperFat
        /// Takes the water ratio the text states; there is no fallback to the model's.
        case settingWaterParts
        /// Takes the fragrance share the text states, else the model's if the text writes it near the keyword.
        case settingFragrancePercentage
        /// Takes the lye type the text states, else the model's, else the one named in a row.
        case settingLyeType
        /// Takes the lye purity the text states.
        case settingLyePurity
        /// Applies a stated KOH share with each lye's own purity, and clears the
        /// single lye type and purity. After the lye type and purity steps.
        case settingHybridLye
        /// Sets the Failor neutraliser and removes its own rows. Reads the lye
        /// type settled by the steps above.
        case settingFailorNeutralizer

        // swiftlint:disable:next cyclomatic_complexity
        func apply(to draft: RecipeImportDraft, context: Context) -> RecipeImportDraft {
            var checked = draft
            switch self {
            case .keepingStatedAmounts:
                checked.oils = Checker.keepingStatedAmounts(checked.oils, numbers: context.numbers)
                checked.additives = Checker.keepingStatedAmounts(checked.additives, numbers: context.numbers)
                checked.fragrances = Checker.keepingStatedAmounts(checked.fragrances, numbers: context.numbers)
            case .movingMisplacedRows:
                checked = Checker.movingMisplacedRows(checked)
            case .removingDuplicates:
                checked = Checker.removingDuplicates(checked)
            case .droppingSectionHeaders:
                checked = checked.droppingSectionHeaders()
            case .checkingBatchSize:
                checked.batchSize = checked.batchSize.flatMap {
                    RecipeTextNumbers.contains($0, in: context.numbers) ? $0 : nil
                }
            case .readingOilAmounts:
                checked = Checker.oilTableRecipe(checked, in: context.text)
                    ?? Checker.statedPercentageRecipe(checked, in: context.text)
                    ?? Checker.matchingOilUnits(checked)
            case .readingSharesAsPercentages:
                checked = Checker.readingSharesAsPercentages(checked, in: context.text)
            case .clearingStaleBatchSize:
                checked = Checker.clearingStaleBatchSize(checked)
            case .settingSuperFat:
                checked.superFat = context.stated.superFat ?? Checker.valueNear(
                    checked.superFat, keyword: RecipeTextSettingsParser.superFatKeyword,
                    in: context.text, requiringPercent: false
                )
            case .settingWaterParts:
                // No fallback for the water ratio: a number beside "water" or "lye"
                // is nearly always a weight, and "4.5 oz lye" read as 4.5 parts
                // water is still inside the plausible range.
                checked.waterParts = context.stated.waterParts
            case .settingFragrancePercentage:
                checked.fragrancePercentage = context.stated.fragrancePercentage ?? Checker.valueNear(
                    checked.fragrancePercentage, keyword: RecipeTextSettingsParser.fragranceKeyword,
                    in: context.text, requiringPercent: true
                )
            case .settingLyeType:
                checked.lyeType = context.stated.lyeType ?? checked.lyeType ?? context.lyeTypeFromRows
            case .settingLyePurity:
                if let lyePurity = context.stated.lyePurity { checked.lyePurity = lyePurity }
            case .settingHybridLye:
                checked = Checker.applyingHybridLye(checked, stated: context.stated)
            case .settingFailorNeutralizer:
                checked = Checker.applyingFailorNeutralizer(checked, stated: context.stated)
            }
            return checked
        }
    }

    private static func applyingHybridLye(_ draft: RecipeImportDraft, stated: RecipeTextSettings) -> RecipeImportDraft {
        guard let kohPercentage = stated.kohPercentage else { return draft }
        // A hybrid is described the way a SoapWiz copy's is: the shares and
        // each lye's own purity, with no single lye type or purity.
        var hybrid = draft
        hybrid.kohPercentage = kohPercentage
        hybrid.kohPurity = stated.kohPurity
        hybrid.naohPurity = stated.naohPurity
        hybrid.lyeType = nil
        hybrid.lyePurity = nil
        return hybrid
    }

    private static func applyingFailorNeutralizer(
        _ draft: RecipeImportDraft,
        stated: RecipeTextSettings
    ) -> RecipeImportDraft {
        var checked = draft
        let neutralizer = failorNeutralizer(for: checked, statedInText: stated.cfmNeutralizer)
        checked.cfmNeutralizer = neutralizer
        guard let neutralizer else { return checked }
        // Only the chosen neutraliser's own rows are pulled out. A recipe that
        // named a second, different one — borax alongside boric acid — keeps it
        // as an ordinary additive rather than losing it silently.
        func isChosenNeutralizer(_ row: ImportedIngredient) -> Bool {
            ImportedIngredientName.failorNeutralizer(named: row.name) == neutralizer
        }
        checked.oils.removeAll(where: isChosenNeutralizer)
        checked.additives.removeAll(where: isChosenNeutralizer)
        checked.fragrances.removeAll(where: isChosenNeutralizer)
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

    /// Drops lye, water and setting rows, and zeroes amounts the text never writes.
    private static func keepingStatedAmounts(
        _ ingredients: [ImportedIngredient],
        numbers: [Double]
    ) -> [ImportedIngredient] {
        ingredients.compactMap { ingredient in
            guard !ImportedIngredientName.isLye(ingredient.name),
                  !ImportedIngredientName.isWater(ingredient.name),
                  !ImportedIngredientName.isSetting(ingredient.name) else { return nil }
            guard ingredient.amount != 0, !RecipeTextNumbers.contains(ingredient.amount, in: numbers) else {
                // A water row with a note in place of a quantity — "Distilled
                // water for dilution, as needed" — is not an ingredient to keep.
                return ingredient.amount == 0 && ImportedIngredientName.isWaterWithNote(ingredient.name)
                    ? nil : ingredient
            }
            var unstated = ingredient
            unstated.amount = 0
            return ImportedIngredientName.isWaterWithNote(unstated.name) ? nil : unstated
        }
    }
}
