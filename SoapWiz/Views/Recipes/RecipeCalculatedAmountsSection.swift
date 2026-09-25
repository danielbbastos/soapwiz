import SwiftUI

/// The collapsible calculated-amounts table beneath a recipe's ingredients:
/// every line item at its resolved weight and its share of the batch.
///
/// Self-contained — owns its expand state and reads its rows from the view
/// model — matching `RecipeExtraIngredientsSection`, which sits directly below
/// it in the same form.
struct RecipeCalculatedAmountsSection: View {
    @Bindable var model: RecipeFormViewModel
    @State private var expanded = true

    @ViewBuilder
    var body: some View {
        if let rows = model.calculatedAmountRows {
            Section(header: CollapsibleSectionHeader(title: "Calculated amounts", expanded: $expanded)
                .expandingSectionHeader(RecipeFormSection.calculatedAmounts, expanded: expanded)) {
                if expanded {
                    VStack(spacing: 0) {
                        header
                        ForEach(rows) { row in
                            Divider().padding(.leading, row.isSummary ? 0 : 16)
                            amountRow(row.label, weight: row.weight, pct: row.pct, summary: row.isSummary, note: row.note)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .expandingSectionEnd(RecipeFormSection.calculatedAmounts)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Ingredient")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Weight")
                .frame(width: 90, alignment: .trailing)
            Text("%")
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .font(.footnote)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .background(Color.cardBackground)
    }

    private func amountRow(_ label: String, weight: Double, pct: Double?, summary: Bool, note: String? = nil) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .lineLimit(1)
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatWeight(weight))
                .frame(width: 90, alignment: .trailing)
                .monospacedDigit()
            Text(pct.map(formatPct) ?? "")
                .frame(width: 64, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .font(.footnote)
        .fontWeight(summary ? .medium : .regular)
        .foregroundStyle(summary ? Color.primary : Color.secondary)
    }

    private func formatWeight(_ value: Double) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(0...2)).grouping(.automatic))
        return "\(formatted) \(model.displayWeightUnit)"
    }

    private func formatPct(_ pct: Double) -> String {
        (pct / 100).formatted(.percent.precision(.fractionLength(1)))
    }
}
