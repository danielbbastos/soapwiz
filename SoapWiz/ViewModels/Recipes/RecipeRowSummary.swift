import Foundation

/// One oil's share of a recipe, as the list row's composition line names it.
///
/// `amount` is a percentage or an absolute weight depending on the recipe's
/// mode — see `RecipeRowSummary.sharesArePercentages`. Carried as a number
/// rather than a formatted string so ordering can be asserted without a test
/// having to reproduce the locale's decimal separator.
struct RecipeOilShare {
    let name: String
    let amount: Double
}

/// Everything the recipe list row shows beneath the name, resolved once per row.
///
/// A value type rather than a set of computed properties on the view because the
/// composition line walks `Recipe.ingredients` — a to-many traversal — and the
/// row is built for every recipe the list holds. `RecipeRowView` builds this in
/// its `init` so a `body` re-evaluation does not repeat the traversal.
///
/// Cost is deliberately absent. `RecipeCostCalculator` is shaped for the form's
/// drafts and needs a `LyeCalculator`, which nothing builds from a persisted
/// `Recipe`; pricing a row would mean walking every purchase of every ingredient
/// mid-scroll. SW-117 took the ingredient count instead of caching a derived
/// value on the model.
struct RecipeRowSummary {
    /// How many oils the composition line names before it gives up and truncates.
    static let compositionLimit = 3

    let soapType: SoapType

    /// Total oil weight of the batch, expressed in `displayWeightUnit`. Zero
    /// when the recipe has nothing to size yet, which the subtitle omits rather
    /// than printing as "0 g".
    let oilWeight: Double

    /// The unit the batch size — and each oil amount in absolute mode — is in.
    /// Mirrors `RecipeFormViewModel.displayWeightUnit`.
    let displayWeightUnit: String

    /// Whether each oil's `amount` is a percentage of the batch or an absolute
    /// weight.
    ///
    /// `Recipe.weightUnit` is the mode switch for the whole oil model, and
    /// `RecipeIngredient.percentage` stores the entered amount in *both* modes —
    /// so in absolute mode that field holds grams despite its name. Reading it
    /// as a percentage regardless is what made a 700 g oil render as "700%".
    let sharesArePercentages: Bool

    /// Highest share first, capped at `compositionLimit`.
    let topOils: [RecipeOilShare]
    let ingredientCount: Int

    /// The recipe's own description, `nil` when it is blank or only whitespace.
    ///
    /// Shown on its own line rather than only as a stand-in for a missing
    /// composition: the two say different things, and the description is often
    /// the only part that distinguishes two recipes built from the same oils.
    let summaryDescription: String?

    /// Soap type and batch size, e.g. "Solid bar soap · 1,000 g".
    ///
    /// Drops to the soap type alone when there is no weight to state. A recipe
    /// in percentage mode that has not been given a total oil weight would
    /// otherwise announce itself as "0 g".
    var subtitle: String {
        guard oilWeight > 0 else { return soapType.label }
        return "\(soapType.label) · \(formatted(oilWeight)) \(displayWeightUnit)"
    }

    /// The composition line — "Olive 70% · Coconut 20%" in percentage mode,
    /// "Olive 700 g · Coconut 200 g" in absolute mode.
    /// `nil` when the recipe names no oils yet, so the row can omit the line.
    var composition: String? {
        guard !topOils.isEmpty else { return nil }
        return topOils.map(label(for:)).joined(separator: " · ")
    }

    var footnote: String {
        ingredientCount == 1 ? "1 item" : "\(ingredientCount) items"
    }

    init(recipe: Recipe) {
        soapType = SoapType.classify(
            useHybrid: recipe.useHybrid,
            naohPercentage: recipe.naohPercentage,
            lyeType: recipe.lyeType
        )
        let usesPercentages = recipe.weightUnit == RecipeRowSummary.percentageUnit
        sharesArePercentages = usesPercentages
        displayWeightUnit = usesPercentages ? recipe.oilWeightUnit : recipe.weightUnit

        let trimmedDescription = recipe.desc.trimmingCharacters(in: .whitespacesAndNewlines)
        summaryDescription = trimmedDescription.isEmpty ? nil : trimmedDescription

        let ingredients = recipe.ingredients
        ingredientCount = ingredients.count

        let oilLines = ingredients.filter { $0.ingredientRole == .oil && $0.percentage > 0 }
        // Named oils are gathered before the cap, not after: a row whose
        // ingredient has not arrived yet would otherwise consume one of the
        // three slots and leave the line a name short. `RecipeIngredient`
        // documents that nil — a sync race can deliver the line before the
        // ingredient it points at.
        //
        // Name breaks amount ties so the line is stable between launches;
        // `sorted(by:)` gives no such guarantee on its own.
        let shares: [RecipeOilShare] = oilLines.compactMap { line in
            guard let name = line.ingredient?.name, !name.isEmpty else { return nil }
            return RecipeOilShare(name: name, amount: line.percentage)
        }
        let ranked = shares.sorted { first, second in
            if first.amount == second.amount { return first.name < second.name }
            return first.amount > second.amount
        }
        topOils = Array(ranked.prefix(RecipeRowSummary.compositionLimit))

        // In absolute mode nothing writes `totalOilWeight` — the form only
        // offers that field in percentage mode — so the batch size has to be
        // summed from the oils themselves, exactly as `LyeCalculator` does.
        // Every oil line counts, named or not: an unresolved line still has
        // mass in the pot.
        oilWeight = usesPercentages
            ? recipe.totalOilWeight
            : oilLines.reduce(0) { $0 + $1.percentage }
    }

    private static let percentageUnit = "%"

    private func label(for share: RecipeOilShare) -> String {
        sharesArePercentages
            ? "\(share.name) \(share.amount.formatted(.number.precision(.fractionLength(0...1))))%"
            : "\(share.name) \(formatted(share.amount)) \(displayWeightUnit)"
    }

    private func formatted(_ weight: Double) -> String {
        weight.formatted(.number.precision(.fractionLength(0...2)))
    }
}
