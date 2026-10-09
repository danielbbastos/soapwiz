import SwiftUI

/// What the model is reading, shown filling in.
///
/// The extraction used to be one indeterminate spinner, which on a long recipe
/// is indistinguishable from a hang. Here the recipe grows on screen as the
/// stream arrives — name, then oils, then the rest — with a status line naming
/// the current step so even an empty first snapshot says something.
struct RecipeImportProgressView: View {
    let draft: RecipeImportDraft?
    let status: String

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color.inkSoft)
                    Text(status)
                        .foregroundStyle(Color.inkSoft)
                }
                .ledgerSheetRow(position: .only)
            }

            if let draft, draft.hasAnyIngredient {
                if !draft.name.isEmpty {
                    Section {
                    } header: {
                        Text(draft.name)
                            .font(.title2.weight(.semibold))
                            .fontDesign(.serif)
                            .foregroundStyle(Color.ink)
                            .textCase(nil)
                            .accessibilityAddTraits(.isHeader)
                    }
                }

                ingredientSection("Oils", draft.oils, in: draft)
                ingredientSection("Additives", draft.additives, in: draft)
                ingredientSection("Fragrances", draft.fragrances, in: draft)
                settingsSection(draft)
            }
        }
        .environment(\.defaultMinListRowHeight, 48)
        .animation(.default, value: draft)
    }

    // MARK: - Sections

    @ViewBuilder
    private func ingredientSection(
        _ title: String,
        _ ingredients: [ImportedIngredient],
        in draft: RecipeImportDraft
    ) -> some View {
        if !ingredients.isEmpty {
            Section {
                ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
                    HoneyLedgerLabeledRow(ingredient.name) {
                        Text.honeyLedgerFigure(amountText(for: ingredient, in: draft))
                    }
                    .ledgerSheetRow(position: .position(index: index, count: ingredients.count))
                }
            } header: {
                HoneyLedgerSectionLabel(title)
            }
        }
    }

    @ViewBuilder
    private func settingsSection(_ draft: RecipeImportDraft) -> some View {
        if draft.statesLyeSettings {
            let rows = draft.statedLyeSettingRows
            Section {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HoneyLedgerLabeledRow(row.title) {
                        Text.honeyLedgerFigure(row.value)
                    }
                    .ledgerSheetRow(position: .position(index: index, count: rows.count))
                }
            } header: {
                HoneyLedgerSectionLabel("Lye Settings")
            }
        }
    }

    // MARK: - Helpers

    /// Mirrors the review screen's amount column so a row reads the same before
    /// and after the stream finishes.
    private func amountText(for ingredient: ImportedIngredient, in draft: RecipeImportDraft) -> String {
        let amount = ingredient.amount
        guard amount > 0 else { return "—" }
        let formatted = PercentageFormatter.string(amount)
        guard let unit = ingredient.unit else {
            return draft.amountsArePercentages ? "\(formatted)%" : "\(formatted) \(draft.resolvedBatchUnit)"
        }
        return unit == "%" ? "\(formatted)%" : "\(formatted) \(unit)"
    }
}
