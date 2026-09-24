import Foundation
import SwiftData

/// Renders a recipe for the clipboard: readable text for a person ("Copy
/// Recipe") or the exact payload for another SoapWiz user ("Copy for SoapWiz").
///
/// The numbers are reached the same way the recipe detail screen reaches them —
/// through `RecipeFormViewModel` — so a pasted recipe and the screen it was
/// copied from can never disagree. Amounts are formatted in the current locale,
/// like everywhere else in the app: the text is for a person to read, not for
/// the app to parse back.
@MainActor
enum RecipeTextExporter {

    /// What "Copy for SoapWiz" puts on the clipboard: the exact payload on its
    /// own, since the only thing that reads it is the importer, which decodes
    /// the marker and never looks at any surrounding text. The human-readable
    /// copy is "Copy Recipe" (`text(for:)`), a separate menu action.
    ///
    /// Falls back to the readable text if the payload can't be encoded, so the
    /// clipboard is never left empty.
    static func soapwizText(for recipe: Recipe) -> String {
        RecipeTransferMarker.line(for: RecipeTransferEncoder.payload(for: [recipe])) ?? text(for: recipe)
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
            settingsLine(model)
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
        return "Collections: \(names.map(listed).joined(separator: ", "))"
    }

    /// A name holding a comma is quoted, CSV-style, so the list reads back into
    /// the same names: "Kids, Sensitive Skin" is one collection, not two.
    private static func listed(_ name: String) -> String {
        guard name.contains(",") || name.hasPrefix("\"") else { return name }
        return "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
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

    /// One line standing in for the whole "Calculated amounts" table: enough of
    /// the lye configuration to reproduce the recipe from the readable text, and
    /// nothing a reader has to scroll past. Only soap recipes have a lye setup,
    /// so a general recipe gets no line at all.
    private static func settingsLine(_ model: RecipeFormViewModel) -> String? {
        guard model.makesSoap, !model.oilDrafts.isEmpty else { return nil }

        var segments = [lyeSegment(model), "\(number(model.superFat))% superfat", "water \(number(model.waterParts)):1"]
        if model.useCFM { segments.append("Failor method (\(model.cfmNeutralizer.displayName.lowercased()))") }
        if model.isCreamSoap { segments.append("cream soap method") }
        return segments.joined(separator: " · ")
    }

    /// The purity is spelled out because it moves the lye weight: the same
    /// recipe at 90% and at 99% KOH needs different amounts.
    private static func lyeSegment(_ model: RecipeFormViewModel) -> String {
        guard model.useHybrid else { return "\(model.lyeType) (\(number(model.lyePurity))% pure)" }
        let split = "\(number(model.kohPercentage))/\(number(model.naohPercentage))"
        let purities = "\(number(model.kohPurity))%/\(number(model.naohPurity))%"
        return "KOH/NaOH \(split) (\(purities) pure)"
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
