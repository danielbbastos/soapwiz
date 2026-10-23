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
        .environment(\.defaultMinListRowHeight, 48)
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

    /// Only what the source actually said.
    ///
    /// The lye rows used to show unconditionally, so a pasted candle or balm
    /// recipe came back reporting "Lye: NaOH" — a claim the text never made, on
    /// the one screen whose job is to show what was understood. Each row now
    /// appears only when the source stated it, and a recipe that mentions no
    /// saponification at all says so plainly instead of being described in
    /// soap-making terms.
    private var settingsSection: some View {
        let values = settingValues
        let notes = settingNotes
        let count = values.count + notes.count
        return Section {
            ForEach(Array(values.enumerated()), id: \.offset) { index, row in
                HoneyLedgerLabeledRow(row.title) {
                    Text.honeyLedgerFigure(row.value)
                }
                .ledgerSheetRow(position: .position(index: index, count: count))
            }
            ForEach(Array(notes.enumerated()), id: \.offset) { index, note in
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
                    .ledgerSheetRow(position: .position(index: values.count + index, count: count))
            }
        } header: {
            HoneyLedgerSectionLabel("Recipe")
        }
    }

    @ViewBuilder
    private func ingredientSection(_ role: RecipeIngredientRole, title: String) -> some View {
        let rows = model.rows.filter { $0.role == role }
        if !rows.isEmpty {
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    RecipeImportRowView(
                        row: row,
                        amountText: draftSummary.amountText(for: row.imported, role: row.role),
                        onCreate: { creatingRow = row },
                        onSkip: { model.skip(row.id) },
                        onUnskip: { model.unskip(row.id) }
                    )
                    .ledgerSheetRow(position: .position(index: index, count: rows.count))
                }
            } header: {
                HoneyLedgerSectionLabel(title)
            }
        }
    }

    private var confirmSection: some View {
        Section {
            HoneyLedgerActionRow("Continue to Recipe") {
                guard let prepared = model.prepared else { return }
                onConfirm(prepared)
            }
            .disabled(!model.canConfirm)
            .ledgerSheetRow(position: .first)
            HoneyLedgerActionRow("Back to Text", isPrimary: false) { model.returnToInput() }
                .ledgerSheetRow(position: .last)
        } footer: {
            if let blocker = model.confirmBlocker {
                HoneyLedgerFieldNote(blocker, tint: .danger)
            } else {
                Text(Self.chemistryNote)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
        }
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

    private var settingValues: [RecipeImportSettingRow] {
        var rows = draftSummary.statedLyeSettingRows
        if let fragrance = draftSummary.fragrancePercentage {
            rows.append(RecipeImportSettingRow(title: "Fragrance", value: "\(PercentageFormatter.string(fragrance))%"))
        }
        return rows
    }

    private var settingNotes: [String] {
        var notes: [String] = []
        if let neutralizer = draftSummary.cfmNeutralizer {
            notes.append("\(neutralizer.displayName) becomes the Catherine Failor neutraliser. The app "
                         + "doses it from the soap weight, so it isn't added as an ingredient here.")
        }
        if !draftSummary.statesLyeSettings {
            notes.append("No lye settings found. The recipe opens with the form's defaults, "
                         + "which you can change — or turn off soap making entirely in Config.")
        }
        if let trimmedNote {
            notes.append(trimmedNote)
        }
        return notes
    }

    private var trimmedNote: String? {
        guard let sanitized = model.sanitized, sanitized.wasTrimmed else { return nil }
        return "Read the recipe out of \(sanitized.originalLength) characters of pasted text."
    }

    private func category(named name: String) -> IngredientCategory? {
        categories.first { $0.name.lookupKey == name.lookupKey }
    }
}
