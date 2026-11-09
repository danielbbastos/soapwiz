import Foundation
import SwiftData

/// One line of Home's "You can make" card.
struct MakeableRecipeRow: Identifiable {
    let recipe: Recipe
    /// Whole batches stock covers; zero when the recipe is short.
    let batches: Int
    /// "Made 4 times · last Oct 15" for a covered recipe made before, or what
    /// is short for a short one. Nil for a covered recipe never made.
    let detail: String?

    var id: PersistentIdentifier { recipe.persistentModelID }
    var isShort: Bool { batches == 0 }
    var batchesText: String { "×\(batches)" }
}

/// Which recipes Home offers to make, and how it describes each.
///
/// Holds the one long-lived `RecipeCoverage`, which caches each recipe's
/// requirements between calls.
@MainActor
final class YouCanMakeModel {
    /// Rows the card shows at most; covered recipes fill them first.
    static let maxRows = 4

    private let coverage = RecipeCoverage()
    private let calendar: Calendar
    private let locale: Locale

    init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar
        self.locale = locale
    }

    private struct Candidate {
        let row: MakeableRecipeRow
        let shortageCount: Int
        let lastMade: Date?
    }

    private struct MadeSummary {
        var count = 0
        var last: Date?
    }

    /// Empty when tracking is off or no recipe has requirements, which hides
    /// the card.
    func rows( // swiftlint:disable:this function_parameter_count
        recipes: [Recipe],
        ingredients: [Ingredient],
        purchases: [IngredientPurchase],
        batches: [Batch],
        tracksInventory: Bool,
        now: Date
    ) -> [MakeableRecipeRow] {
        coverage.prune(keeping: recipes)
        guard tracksInventory, !recipes.isEmpty else { return [] }

        let stock = StockLevels(purchases)
        let stored = ingredients.filter { $0.modelContext != nil }
        let lyes = stored.filter { $0.category?.name == IngredientCategory.Name.lyes && !$0.isHidden }
        let additives = stored.filter { $0.category?.name == IngredientCategory.Name.additives && !$0.isHidden }
        let made = madeSummaries(batches)

        var covered: [Candidate] = []
        var short: [Candidate] = []
        for recipe in recipes where recipe.modelContext != nil {
            let result = coverage.coverage(
                for: recipe,
                stock: stock,
                lyeCandidates: RecipeFormViewModel.lyeCandidates(
                    visible: lyes,
                    keeping: [recipe.lyeIngredient, recipe.kohLyeIngredient]
                ),
                neutralizerCandidates: RecipeFormViewModel.neutralizerCandidates(
                    visible: additives,
                    keeping: [recipe.neutralizerIngredient]
                ),
                tracksInventory: tracksInventory
            )
            guard let result else { continue }
            let summary = made[recipe.persistentModelID]
            let detail = result.batches > 0
                ? madeText(count: summary?.count ?? 0, last: summary?.last, now: now)
                : shortText(result.shortages)
            let candidate = Candidate(
                row: MakeableRecipeRow(recipe: recipe, batches: result.batches, detail: detail),
                shortageCount: result.shortages.count,
                lastMade: summary?.last
            )
            if result.batches > 0 { covered.append(candidate) } else { short.append(candidate) }
        }

        covered.sort { lhs, rhs in
            if lhs.row.batches != rhs.row.batches { return lhs.row.batches > rhs.row.batches }
            return Self.recencyThenName(lhs, rhs)
        }
        short.sort { lhs, rhs in
            if lhs.shortageCount != rhs.shortageCount { return lhs.shortageCount < rhs.shortageCount }
            return Self.recencyThenName(lhs, rhs)
        }
        return (covered + short).prefix(Self.maxRows).map(\.row)
    }

    private static func recencyThenName(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        let left = lhs.lastMade ?? .distantPast
        let right = rhs.lastMade ?? .distantPast
        if left != right { return left > right }
        return lhs.row.recipe.name.localizedStandardCompare(rhs.row.recipe.name) == .orderedAscending
    }

    private func madeSummaries(_ batches: [Batch]) -> [PersistentIdentifier: MadeSummary] {
        var summaries: [PersistentIdentifier: MadeSummary] = [:]
        for batch in batches where !batch.isDeleted && batch.modelContext != nil {
            guard let recipe = batch.recipe, !recipe.isDeleted, recipe.modelContext != nil else { continue }
            var summary = summaries[recipe.persistentModelID] ?? MadeSummary()
            summary.count += 1
            summary.last = max(summary.last ?? batch.dateCreated, batch.dateCreated)
            summaries[recipe.persistentModelID] = summary
        }
        return summaries
    }

    func madeText(count: Int, last: Date?, now: Date) -> String? {
        guard count > 0, let last else { return nil }
        let made: String
        switch count {
        case 1: made = String(localized: "Made once")
        case 2: made = String(localized: "Made twice")
        default: made = String(localized: "Made \(count) times")
        }
        return String(localized: "\(made) · last \(dateText(last, now: now))")
    }

    func dateText(_ date: Date, now: Date) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar).month(.abbreviated).day()
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
            style = style.year()
        }
        return date.formatted(style)
    }

    func shortText(_ shortages: [BatchRequirement]) -> String? {
        guard let first = shortages.first else { return nil }
        let amount = BatchAmountFormat.amount(first.shortfall, unit: first.unit)
        let others = shortages.count - 1
        if others > 0 {
            return String(localized: "Short on \(first.ingredient.name), \(amount) and \(others) more")
        }
        return String(localized: "Short on \(first.ingredient.name), \(amount)")
    }
}
