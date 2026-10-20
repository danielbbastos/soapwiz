import Foundation

/// Which oil amounts an import keeps, and which unit they are in.
///
/// A recipe that writes each oil as both a share and a weight — "Palm Oil 35%
/// (210 g)" — gives the model two true numbers per line, and on device it has
/// taken the weights while still reporting the amounts as percentages. Both
/// numbers appear in the text, so the invented-amount check can't catch it,
/// and the form then opened with oils totalling 600%.
extension RecipeImportDraftChecker {
    private static let statedShare = #/(\d(?:[\d\h.,']*\d)?)\h*%/#
    private static let statedWeight = #/(?i)(\d(?:[\d\h.,']*\d)?)\h*(kg|grams?|grs?|g|oz|lb)\b/#

    /// Shares that add up to this are a whole blend, allowing for rounding in
    /// the source.
    static let wholeBlend = 98.0...102.0

    /// The draft as a percentage recipe, when the text writes a percentage
    /// beside every oil; `nil` otherwise.
    ///
    /// A recipe that states its oils as shares is a percentage recipe, whatever
    /// the model reported and whatever weights are written alongside: each oil
    /// takes the share on its line. When every line also carries a weight in
    /// one unit, their sum is the batch size; otherwise the batch size stays as
    /// checked. Shares that don't make a whole blend are more likely a misread
    /// than a recipe, and leave the draft to the model.
    static func statedPercentageRecipe(_ draft: RecipeImportDraft, in text: String) -> RecipeImportDraft? {
        let lines = text.components(separatedBy: .newlines)
        var stated: [StatedOilAmount] = []
        for oil in draft.oils {
            let amounts = lines
                .filter { $0.lookupKey.contains(oil.name.lookupKey) }
                .compactMap(statedOilAmount)
            // Not simply the first line naming the oil: a description such as
            // "built on olive oil" comes before the ingredient list, so the line
            // holding the model's own number wins.
            guard let amount = amounts.first(where: { $0.accounts(for: oil.amount) }) ?? amounts.first else {
                return nil
            }
            stated.append(amount)
        }
        guard wholeBlend.contains(stated.map(\.share).reduce(0, +)) else { return nil }

        var recipe = draft
        for (index, amount) in zip(recipe.oils.indices, stated) {
            recipe.oils[index].amount = amount.share
            recipe.oils[index].unit = "%"
        }
        recipe.amountsArePercentages = true
        let weights = stated.compactMap(\.weight)
        let units = Set(weights.map(\.unit))
        if weights.count == stated.count, units.count == 1, let unit = units.first {
            recipe.batchSize = (weights.map(\.value).reduce(0, +) * 100).rounded() / 100
            recipe.batchUnit = unit
        }
        return recipe
    }

    /// The draft with `amountsArePercentages` agreeing with the units written
    /// beside the oils, for a recipe whose text doesn't state them as shares.
    ///
    /// The review screen shows each oil in the draft's unit and the form opens
    /// in it, so a draft whose rows say "g" but whose flag says percentages
    /// would put 210 g on one screen and 210% on the other. When every oil with
    /// an amount carries the same unit, that unit wins; mixed or missing units
    /// leave the flag as the model set it.
    static func matchingOilUnits(_ draft: RecipeImportDraft) -> RecipeImportDraft {
        let units = draft.oils
            .filter { $0.amount > 0 }
            .map(\.normalizedUnit)
        guard let unit = units.first ?? nil, units.allSatisfy({ $0 == unit }) else { return draft }

        var matched = draft
        if unit == "%" {
            matched.amountsArePercentages = true
        } else if RecipeImportDraft.supportedWeightUnits.contains(unit) {
            matched.amountsArePercentages = false
            matched.batchUnit = unit
        }
        return matched
    }

    /// The draft as a percentage recipe, when its "weights" are really shares.
    ///
    /// A SoapCalc table prints its % column without a percent sign, and beside
    /// a stated total oil weight the model has read "40" as 40 g. A weight
    /// recipe whose oils add up to a whole blend while its batch size is
    /// something else is that misread: real weights summing to about 100 are
    /// only possible in a batch of about 100, and then the draft is left alone.
    /// Needs a stated batch size to compare against; without one the amounts
    /// can't be told from a small genuine recipe.
    static func readingSharesAsPercentages(_ draft: RecipeImportDraft) -> RecipeImportDraft {
        guard !draft.amountsArePercentages, let batchSize = draft.batchSize,
              !wholeBlend.contains(batchSize),
              wholeBlend.contains(draft.oils.map(\.amount).reduce(0, +)) else { return draft }

        var recipe = draft
        for index in recipe.oils.indices where recipe.oils[index].amount > 0 {
            recipe.oils[index].unit = "%"
        }
        recipe.amountsArePercentages = true
        return recipe
    }

    /// The draft without a batch size that doesn't describe its oils.
    ///
    /// A mould size ("5-Pound Wood Mold") is a number in the text, so the check
    /// against the text keeps it, and the model has reported it as the batch
    /// beside oils written in ounces. For a weight recipe, whose oils all share
    /// one unit, a batch size that isn't their total to within 1% is cleared
    /// and the review screen shows a gap instead. `matchingOilUnits` has
    /// already put that shared unit on the draft.
    static func clearingStaleBatchSize(_ draft: RecipeImportDraft) -> RecipeImportDraft {
        guard !draft.amountsArePercentages, let batchSize = draft.batchSize else { return draft }
        let weighed = draft.oils.filter { $0.amount > 0 }
        let units = Set(weighed.map(\.normalizedUnit))
        guard units.count == 1, let unit = units.first ?? nil,
              RecipeImportDraft.supportedWeightUnits.contains(unit) else { return draft }

        let total = weighed.map(\.amount).reduce(0, +)
        guard abs(batchSize - total) > total * 0.01 else { return draft }
        var recipe = draft
        recipe.batchSize = nil
        return recipe
    }

    private static func statedOilAmount(in line: String) -> StatedOilAmount? {
        guard let share = line.firstMatch(of: statedShare).flatMap({ RecipeTextExportReader.decimal($0.output.1) }),
              (0...100).contains(share) else { return nil }
        let weight = line.firstMatch(of: statedWeight).flatMap { match -> StatedWeight? in
            let unit = weightUnit(match.output.2.lowercased())
            return weightValue(match.output.1, unit: unit).map { StatedWeight(value: $0, unit: unit) }
        }
        return StatedOilAmount(share: share, weight: weight)
    }

    /// The supported unit a written weight unit stands for: "gr", "grs" and
    /// "grams" are all grams.
    private static func weightUnit(_ written: String) -> String {
        written.hasPrefix("g") ? "g" : written
    }

    /// A weight's number in its unit.
    ///
    /// Ounce and pound amounts never use a thousands separator, so a lone dot or
    /// comma there is the decimal point: "9.524 oz" is not 9524. Grams and
    /// kilograms keep the exporter reading, where "1.000 g" is a thousand.
    private static func weightValue(_ token: Substring, unit: String) -> Double? {
        let separators = token.count { $0 == "." || $0 == "," }
        if unit == "oz" || unit == "lb", separators == 1, let value = RecipeTextNumbers.decimal(token) {
            return value
        }
        return RecipeTextExportReader.decimal(token)
    }
}

/// One oil's line when it states a share of the blend, and the weight beside
/// it when there is one.
private struct StatedOilAmount {
    let share: Double
    let weight: StatedWeight?

    /// Whether the model's amount is one of the numbers on the line.
    func accounts(for amount: Double) -> Bool {
        RecipeTextNumbers.contains(amount, in: [share, weight?.value].compactMap { $0 })
    }
}

private struct StatedWeight {
    let value: Double
    let unit: String
}
