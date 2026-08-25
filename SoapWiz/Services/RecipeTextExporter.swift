import Foundation
import SwiftData

/// Renders a recipe as the plain text "Copy Recipe" puts on the clipboard.
///
/// The numbers are reached the same way the recipe detail screen reaches them —
/// through `RecipeFormViewModel` — so a pasted recipe and the screen it was
/// copied from can never disagree. Amounts are formatted in the current locale,
/// like everywhere else in the app: the text is for a person to read, not for
/// the app to parse back.
@MainActor
enum RecipeTextExporter {

    /// What "Copy Recipe" actually puts on the clipboard: the readable text,
    /// then the exact payload on one final line.
    ///
    /// One action serving two audiences. A person pastes this into a message and
    /// reads the recipe, ignoring the last line; SoapWiz pastes it into the
    /// importer and reads the last line, ignoring the rest. Keeping them in one
    /// clipboard entry is what stops the user having to pick the right copy
    /// command, which they would sometimes get wrong.
    ///
    /// The payload is appended, never substituted: if it can't be built the
    /// readable text still goes to the clipboard on its own.
    static func clipboardText(for recipe: Recipe) -> String {
        let readable = text(for: recipe)
        guard let marker = RecipeTransferMarker.line(for: RecipeTransferEncoder.payload(for: [recipe])) else {
            return readable
        }
        return "\(readable)\n\n\(marker)"
    }

    static func text(for recipe: Recipe) -> String {
        let model = RecipeFormViewModel()
        model.load(from: recipe)
        let batch = model.wholeBatchBreakdown

        let blocks: [String?] = [
            header(recipe),
            collectionsLine(recipe),
            oilsBlock(model),
            amountsBlock("Additives", drafts: model.additiveDrafts, rows: batch.additives, model: model),
            amountsBlock("Fragrances", drafts: model.fragranceDrafts, rows: batch.fragrances, model: model),
            calculatedBlock(model)
        ]
        return blocks.compactMap { $0 }.joined(separator: "\n\n")
    }

    // MARK: - Blocks

    private static func header(_ recipe: Recipe) -> String {
        let name = recipe.name.isEmpty ? "Untitled Recipe" : recipe.name
        guard !recipe.desc.isEmpty else { return name }
        return "\(name)\n\(recipe.desc)"
    }

    private static func collectionsLine(_ recipe: Recipe) -> String? {
        let names = recipe.collections.sortedByName.map(\.name)
        guard !names.isEmpty else { return nil }
        return "Collections: \(names.joined(separator: ", "))"
    }

    private static func oilsBlock(_ model: RecipeFormViewModel) -> String? {
        guard !model.oilDrafts.isEmpty else { return nil }
        let weights = Dictionary(
            (model.oilAmountCalculations ?? []).map { ($0.id, $0.weight) },
            uniquingKeysWith: { first, _ in first }
        )
        let rows = model.oilDrafts
            .sorted { $0.amount > $1.amount }
            .map { draft in
                row(draft.ingredient.name, oilAmountText(draft, batchWeight: weights[draft.id], model: model))
            }
        return block("Oils", rows: rows)
    }

    private static func amountsBlock(
        _ title: String,
        drafts: [IngredientAmountDraft],
        rows breakdown: [IngredientProductBreakdown],
        model: RecipeFormViewModel
    ) -> String? {
        guard !drafts.isEmpty else { return nil }
        let weights = Dictionary(
            breakdown.map { ($0.ingredient.persistentModelID, $0.ingredientAmount) },
            uniquingKeysWith: +
        )
        let rows = drafts.map { draft in
            let weight = weights[draft.ingredient.persistentModelID]
            return row(draft.ingredient.name, amountText(draft, batchWeight: weight, model: model))
        }
        return block(title, rows: rows)
    }

    private static func calculatedBlock(_ model: RecipeFormViewModel) -> String? {
        guard let rows = model.calculatedAmountRows else { return nil }
        let unit = model.displayWeightUnit
        return block("Calculated amounts", rows: rows.map { row($0.label, weightText($0.weight, unit: unit)) })
    }

    // MARK: - Rows

    /// Mirrors `RecipeDetailView.oilAmountText`: a percentage recipe shows the
    /// share with its weight in brackets, an absolute one just the weight.
    private static func oilAmountText(
        _ draft: OilIngredientDraft,
        batchWeight: Double?,
        model: RecipeFormViewModel
    ) -> String {
        let unit = model.displayWeightUnit
        guard model.weightUnitIsPercentage else {
            return weightText(batchWeight ?? draft.amount, unit: unit)
        }
        let primary = "\(model.formatPercentage(draft.amount))%"
        guard let batchWeight else { return primary }
        return "\(primary) (\(weightText(batchWeight, unit: unit)))"
    }

    /// Mirrors `RecipeDetailView.ingredientAmountText`: the converted weight is
    /// spelled out only for a percentage row, since an absolute unit stands alone.
    private static func amountText(
        _ draft: IngredientAmountDraft,
        batchWeight: Double?,
        model: RecipeFormViewModel
    ) -> String {
        let primary = "\(number(draft.amount)) \(draft.unit)"
        guard RecipeUnitOptions.isPercentage(draft.unit), let batchWeight, batchWeight > 0 else { return primary }
        return "\(primary) (\(weightText(batchWeight, unit: model.displayWeightUnit)))"
    }

    // MARK: - Formatting

    private static func block(_ title: String, rows: [String]) -> String {
        ([title] + rows).joined(separator: "\n")
    }

    private static func row(_ label: String, _ value: String) -> String {
        "  \(label) — \(value)"
    }

    private static func weightText(_ value: Double, unit: String) -> String {
        "\(number(value)) \(unit)"
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
