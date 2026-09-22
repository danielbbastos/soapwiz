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
                    Text(status)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.cardBackground)

            if let draft, draft.hasAnyIngredient {
                if !draft.name.isEmpty {
                    Section("Recipe") {
                        Text(draft.name)
                            .font(.headline)
                    }
                    .listRowBackground(Color.cardBackground)
                }

                ingredientSection("Oils", draft.oils, in: draft)
                ingredientSection("Additives", draft.additives, in: draft)
                ingredientSection("Fragrances", draft.fragrances, in: draft)
                settingsSection(draft)
            }
        }
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
            Section(title) {
                ForEach(ingredients) { ingredient in
                    LabeledContent(ingredient.name, value: amountText(for: ingredient, in: draft))
                }
            }
            .listRowBackground(Color.cardBackground)
        }
    }

    @ViewBuilder
    private func settingsSection(_ draft: RecipeImportDraft) -> some View {
        if draft.statesLyeSettings {
            Section("Lye Settings") {
                if let lyeType = draft.lyeType {
                    LabeledContent("Lye", value: lyeType)
                }
                if let superFat = draft.superFat {
                    LabeledContent("Super Fat", value: "\(PercentageFormatter.string(superFat))%")
                }
                if let waterParts = draft.waterParts {
                    LabeledContent("Water : Lye", value: "\(PercentageFormatter.string(waterParts)) : 1")
                }
            }
            .listRowBackground(Color.cardBackground)
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
