import SwiftUI
import SwiftData

/// Where a misread percentage gets caught, and where the chemistry boundary
/// becomes visible rather than mysterious.
///
/// Every extracted row is shown with what it resolved to. Nothing has been
/// written yet — confirming here only opens the recipe form, prefilled.
struct RecipeImportReviewView: View {
    let model: RecipeImportViewModel
    let inventory: [Ingredient]
    var onConfirm: (PreparedRecipeImport) -> Void

    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]
    @State private var creatingRow: RecipeImportRow?

    var body: some View {
        Form {
            settingsSection
            ingredientSection(.oil, title: "Oils")
            ingredientSection(.fragrance, title: "Fragrances")
            ingredientSection(.additive, title: "Additives")
            confirmSection
        }
        .sheet(item: $creatingRow) { row in
            IngredientFormView(
                defaultCategory: category(named: row.suggestedCategoryName),
                prefilledName: row.imported.name
            ) { newIngredient in
                model.resolve(row.id, with: newIngredient, inventory: inventory)
            }
        }
    }

    // MARK: - Sections

    private var settingsSection: some View {
        Section("Recipe") {
            LabeledContent("Lye", value: draftSummary.lyeType)
            if let superFat = draftSummary.superFat {
                LabeledContent("Super Fat", value: "\(PercentageFormatter.string(superFat))%")
            }
            if let waterParts = draftSummary.waterParts {
                LabeledContent("Water : Lye", value: "\(PercentageFormatter.string(waterParts)) : 1")
            }
            if let fragrance = draftSummary.fragrancePercentage {
                LabeledContent("Fragrance", value: "\(PercentageFormatter.string(fragrance))%")
            }
            if let trimmedNote {
                Text(trimmedNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.cardBackground)
    }

    @ViewBuilder
    private func ingredientSection(_ role: RecipeIngredientRole, title: String) -> some View {
        let rows = model.rows.filter { $0.role == role }
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { row in
                    RecipeImportRowView(
                        row: row,
                        amountText: amountText(for: row),
                        onCreate: { creatingRow = row },
                        onSkip: { model.skip(row.id) },
                        onUnskip: { model.unskip(row.id) }
                    )
                }
            }
            .listRowBackground(Color.cardBackground)
        }
    }

    private var confirmSection: some View {
        Section {
            Button("Continue to Recipe") {
                guard let prepared = model.prepared else { return }
                onConfirm(prepared)
            }
            .disabled(!model.canConfirm)
            Button("Back to Text") { model.returnToInput() }
        } footer: {
            Text(model.confirmBlocker ?? Self.chemistryNote)
        }
        .listRowBackground(Color.cardBackground)
    }

    /// Stated plainly, because it is the one thing about this feature a user
    /// could otherwise get dangerously wrong.
    private static let chemistryNote = """
        Saponification values come from your own inventory, never from the imported text. \
        Nothing is saved until you press Save on the recipe.
        """

    // MARK: - Helpers

    private var draftSummary: RecipeImportDraft {
        model.reviewedDraft
    }

    private var trimmedNote: String? {
        guard let sanitized = model.sanitized, sanitized.wasTrimmed else { return nil }
        return "Read the recipe out of \(sanitized.originalLength) characters of pasted text."
    }

    private func amountText(for row: RecipeImportRow) -> String {
        let amount = row.imported.amount
        guard amount > 0 else { return "—" }
        let formatted = PercentageFormatter.string(amount)
        guard let unit = row.imported.unit else {
            return draftSummary.amountsArePercentages ? "\(formatted)%" : "\(formatted) \(draftSummary.resolvedBatchUnit)"
        }
        return unit == "%" ? "\(formatted)%" : "\(formatted) \(unit)"
    }

    private func category(named name: String) -> IngredientCategory? {
        categories.first { $0.name.lookupKey == name.lookupKey }
    }
}
