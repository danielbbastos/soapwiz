import SwiftUI
import SwiftData

/// The collapsible "Extra Ingredients" suggestion table beneath the recipe's
/// ingredients: sodium lactate, citric acid, chelators, antioxidants, and the
/// acid-neutralisation lye sub-rows. Self-contained — owns its expand/percentage
/// state and reads its suggestions from the view model.
struct RecipeExtraIngredientsSection: View {
    @Bindable var model: RecipeFormViewModel
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @State private var expanded = false
    @State private var selectedSectionAPct = 1

    @ViewBuilder
    var body: some View {
        if let data = model.extraIngredientData {
            Section {
                if expanded {
                    // The dosage only applies to the first group, so the line
                    // under it is the darker `inkSoft` a total sits under, run
                    // to both edges of the sheet's content. Both rows share it,
                    // so both tint it; inside `ledgerSheetRow`, whose own
                    // `rule` tint would otherwise win.
                    extraSectionA(rows: data.sectionA)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 16 }
                        .alignmentGuide(.listRowSeparatorTrailing) { $0.width - 16 }
                        .listRowSeparatorTint(Color.inkSoft, edges: .bottom)
                        .ledgerSheetRow(position: .first)
                    extraSectionB(rows: data.sectionB)
                        .padding(.top, 8)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 16 }
                        .alignmentGuide(.listRowSeparatorTrailing) { $0.width - 16 }
                        .listRowSeparatorTint(Color.inkSoft, edges: .top)
                        .ledgerSheetRow(position: .last)
                }
            } header: {
                CollapsibleSectionHeader(title: "Extra Ingredients", expanded: $expanded)
                    .expandingSectionHeader(RecipeFormSection.extraIngredients, expanded: expanded)
            }
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.rule)
            .frame(height: 1)
    }

    // MARK: - Section A (dosage-percentage rows)

    private func extraSectionA(rows: [ExtraSectionARow]) -> some View {
        VStack(spacing: 0) {
            extraSectionAHeader
            ForEach(rows) { row in
                rule.padding(.leading, 16)
                extraSectionARow(label: row.label, weight: value(from: row), isSubrow: false)
                if let naoh = row.naohLye {
                    let naohValue = selectedSectionAPct == 1 ? naoh.val1 : selectedSectionAPct == 2 ? naoh.val2 : naoh.val3
                    extraSectionARow(label: "↳ Extra NaOH", weight: naohValue, isSubrow: true)
                }
                if let koh = row.kohLye {
                    let kohValue = selectedSectionAPct == 1 ? koh.val1 : selectedSectionAPct == 2 ? koh.val2 : koh.val3
                    extraSectionARow(label: "↳ Extra KOH", weight: kohValue, isSubrow: true)
                }
            }
        }
        .listRowInsets(EdgeInsets())
    }

    private func value(from row: ExtraSectionARow) -> Double {
        switch selectedSectionAPct {
        case 1: row.val1
        case 2: row.val2
        default: row.val3
        }
    }

    private var extraSectionAHeader: some View {
        HStack(spacing: 8) {
            Text("Dosage")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.9)
                .foregroundStyle(Color.inkSoft)
            InfoPopoverIcon(title: "Dosage Percentages", text: sectionADosageExplanation)
            Spacer(minLength: 8)
            HoneyLedgerSegmented(
                "Dosage",
                selection: $selectedSectionAPct,
                options: [(1, "1%"), (2, "2%"), (3, "3%")]
            )
            .frame(maxWidth: 200)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sectionADosageExplanation: String {
        "These percentages represent the dosage as a fraction of total oil weight — "
        + "for example, 1% equals 10 g per 1000 g of oils.\n\n"
        + "They are only relevant for Sodium Lactate and Citric Acid Powder."
    }

    private func extraSectionARow(label: String, weight: Double, isSubrow: Bool) -> some View {
        let match = isSubrow ? nil : model.matchedExtraIngredient(label: label, in: inventory)
        return extraRow(ingredient: match, amount: weight) {
            HStack(spacing: 8) {
                if !isSubrow {
                    extraToggleIcon(label: label, ingredient: match)
                }
                Text(label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                Text(formatWeight(weight))
                    .monospacedDigit()
            }
            .padding(.leading, isSubrow ? 32 : 16)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .font(.subheadline)
            .foregroundStyle(isSubrow ? Color.inkSoft : Color.ink)
            .italic(isSubrow)
        }
    }

    // MARK: - Section B (min/max range rows)

    private func extraSectionB(rows: [ExtraSectionBRow]) -> some View {
        VStack(spacing: 0) {
            // The Form already draws a separator above this block, so the first
            // row skips its own divider to avoid a doubled line.
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { rule.padding(.leading, 16) }
                extraSectionBRow(row)
                if let naoh = row.naohLye {
                    extraSectionBSubRow("↳ Extra NaOH", value: naoh)
                }
                if let koh = row.kohLye {
                    extraSectionBSubRow("↳ Extra KOH", value: koh)
                }
            }
        }
        .listRowInsets(EdgeInsets())
    }

    private func extraSectionBRow(_ row: ExtraSectionBRow) -> some View {
        let match = model.matchedExtraIngredient(label: row.label, in: inventory)
        return extraRow(ingredient: match, amount: row.minValue) {
            HStack(spacing: 8) {
                extraToggleIcon(label: row.label, ingredient: match)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .lineLimit(1)
                    if let note = row.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Color.inkSoft)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let max = row.maxValue {
                    Text("\(formatWeight(row.minValue)) – \(formatWeight(max))")
                        .monospacedDigit()
                } else {
                    Text(formatWeight(row.minValue))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .font(.subheadline)
            .foregroundStyle(Color.ink)
        }
    }

    private func extraSectionBSubRow(_ label: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .italic()
            Text(formatWeight(value))
                .monospacedDigit()
        }
        .foregroundStyle(Color.inkSoft)
        .padding(.leading, 32)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
        .font(.subheadline)
    }

    // MARK: - Shared row helpers

    /// Wraps an extras row in a toggle button when its label matched an
    /// inventory ingredient, so tapping anywhere on the row checks or unchecks
    /// the suggestion. Unmatched (or sub-) rows render as-is.
    @ViewBuilder
    private func extraRow<Content: View>(
        ingredient: Ingredient?, amount: Double, @ViewBuilder content: () -> Content
    ) -> some View {
        if let ingredient {
            Button {
                model.toggleExtra(ingredient, amount: amount)
            } label: {
                content()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content()
        }
    }

    /// Checkmark state for an extras row; the dashed placeholder explains how
    /// to enable rows with no matching inventory ingredient.
    @ViewBuilder
    private func extraToggleIcon(label: String, ingredient: Ingredient?) -> some View {
        if let ingredient {
            let isAdded = model.isExtraAdded(ingredient)
            Image(systemName: isAdded ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isAdded ? Color.amberText : Color.inkFaint)
        } else {
            InfoPopoverIcon(
                text: "Not in inventory. Add an ingredient matching “\(label)” to include it in the recipe cost.",
                systemImage: "circle.dashed"
            )
        }
    }

    private func formatWeight(_ value: Double) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(0...2)).grouping(.automatic))
        return "\(formatted) \(model.displayWeightUnit)"
    }
}
