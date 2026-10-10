import SwiftUI

/// The first row of the recipe form's Fragrances sheet: the fragrance target
/// and the unit menu. The add row sits at the foot of the sheet, as on the
/// other ingredient sheets.
///
/// The two share one line when they fit. Otherwise, at the largest text sizes,
/// each takes its own and may wrap rather than run past the row's edge.
struct RecipeFragrancesHeaderRow: View {
    let model: RecipeFormViewModel

    /// The height of the amount field in the fragrance rows under this one,
    /// which is a little taller than a line of text.
    @ScaledMetric(relativeTo: .body) private var amountFieldHeight: CGFloat = 22

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                targetLabel(keepsNaturalWidth: true)
                Spacer()
                unitMenu
                    .fixedSize()
            }
            .frame(minHeight: amountFieldHeight)
            VStack(alignment: .leading) {
                targetLabel(keepsNaturalWidth: false)
                unitMenu
            }
        }
    }

    /// Without a target the row is titled "Unit", like the other menu rows.
    @ViewBuilder
    private func targetLabel(keepsNaturalWidth: Bool) -> some View {
        if let target = model.fragranceTarget {
            HStack(spacing: 4) {
                Text(target.text)
                    .lineLimit(keepsNaturalWidth ? 1 : nil)
                    .foregroundStyle(target.isOverTarget ? Color.danger : Color.inkSoft)
                // Its tap padding would make this row taller than the
                // fragrance rows under it.
                InfoPopoverIcon(text: targetInfoText(for: target))
                    .padding(.vertical, -InfoPopoverIcon.tapPadding)
            }
        } else {
            Text("Unit")
                .foregroundStyle(Color.ink)
                .accessibilityHidden(true)
        }
    }

    /// A menu picker rather than a `Menu`, which keeps its label at the old
    /// value's width while it closes and squeezes a longer unit. Tinted `ink`,
    /// since the picker draws its value in the tint and amber is only ever a
    /// fill. Laid out at the line's height, so this row is no taller than the
    /// fragrance rows under it.
    private var unitMenu: some View {
        Picker("Unit", selection: Binding(
            get: { model.fragranceUnit },
            set: { model.setFragranceUnit($0) }
        )) {
            ForEach(model.availableFragranceUnits, id: \.self) { Text($0.rawValue) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Color.ink)
        .menuPickerLineHeight()
    }

    private func targetInfoText(for target: FragranceTarget) -> String {
        let load = "Recommended fragrance load: "
            + "\(model.formatPercentage(target.percentage))% of total oils, "
            + "set on the Config tab."
        guard model.fragranceUnit == .percentOfFragrances else { return load }
        return load + " Each row is its share of that load; the shares should total 100%."
    }
}
