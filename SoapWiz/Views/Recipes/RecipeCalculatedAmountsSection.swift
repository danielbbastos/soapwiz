import SwiftUI

/// The collapsible calculated-amounts sheet beneath a recipe's ingredients:
/// every line item at its resolved weight and its share of the batch.
///
/// Self-contained — owns its expand state and reads its rows from the view
/// model — matching `RecipeExtraIngredientsSection`, which sits directly below
/// it in the same form.
struct RecipeCalculatedAmountsSection: View {
    @Bindable var model: RecipeFormViewModel
    @State private var expanded = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var weightColumnWidth: CGFloat = 96
    @ScaledMetric(relativeTo: .body) private var percentColumnWidth: CGFloat = 64

    @ViewBuilder
    var body: some View {
        if let rows = model.calculatedAmountRows {
            Section {
                if expanded {
                    // No column heads once the figures stack under the names.
                    let offset = dynamicTypeSize.isAccessibilitySize ? 0 : 1
                    let count = rows.count + offset
                    if offset == 1 {
                        columnHeader
                            .ledgerSheetRow(position: .position(index: 0, count: count))
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        // A total sits under a hairline in `inkSoft` rather than
                        // the pale `rule`. That hairline is shared with the row
                        // above, so both rows tint it.
                        let precedesTotal = rows.indices.contains(index + 1) && rows[index + 1].isSummary
                        // Inside `ledgerSheetRow`, whose own `rule` tint would
                        // otherwise win.
                        amountRow(row)
                            .listRowSeparatorTint(row.isSummary ? Color.inkSoft : Color.rule, edges: .top)
                            .listRowSeparatorTint(precedesTotal ? Color.inkSoft : Color.rule, edges: .bottom)
                            .ledgerSheetRow(position: .position(index: index + offset, count: count))
                    }
                }
            } header: {
                CollapsibleSectionHeader(title: "Calculated amounts", expanded: $expanded)
                    .expandingSectionHeader(RecipeFormSection.calculatedAmounts, expanded: expanded)
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("Ingredient")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Weight")
                .frame(width: weightColumnWidth, alignment: .trailing)
            Text("%")
                .frame(width: percentColumnWidth, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .textCase(.uppercase)
        .tracking(0.9)
        .foregroundStyle(Color.inkSoft)
        .accessibilityHidden(true)
    }

    /// A total is set semibold, its figures in `ink`; the other rows keep the
    /// name in `ink` and the figures beside it in `inkSoft`.
    /// At accessibility text sizes the figures move under the name, since
    /// three columns no longer fit beside it.
    @ViewBuilder
    private func amountRow(_ row: CalculatedAmountRow) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    label(row)
                    HStack(spacing: 12) {
                        weight(row)
                        percent(row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    label(row)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    weight(row)
                        .frame(width: weightColumnWidth, alignment: .trailing)
                    percent(row)
                        .frame(width: percentColumnWidth, alignment: .trailing)
                }
            }
        }
        .font(.subheadline)
        .fontWeight(row.isSummary ? .semibold : nil)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    private func label(_ row: CalculatedAmountRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.label)
                .foregroundStyle(Color.ink)
            if let note = row.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
        }
    }

    private func weight(_ row: CalculatedAmountRow) -> some View {
        Text(formatWeight(row.weight))
            .fontWeight(row.isSummary ? .semibold : .medium)
            .foregroundStyle(Color.ink)
    }

    private func percent(_ row: CalculatedAmountRow) -> some View {
        Text(row.pct.map(formatPct) ?? "")
            .foregroundStyle(row.isSummary ? Color.ink : Color.inkSoft)
    }

    private func formatWeight(_ value: Double) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(0...2)).grouping(.automatic))
        return "\(formatted) \(model.displayWeightUnit)"
    }

    private func formatPct(_ pct: Double) -> String {
        (pct / 100).formatted(.percent.precision(.fractionLength(1)))
    }
}
