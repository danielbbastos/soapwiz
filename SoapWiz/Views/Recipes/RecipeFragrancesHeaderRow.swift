import SwiftUI

/// The first row of the recipe form's Fragrances section: the add button, the
/// fragrance target and the unit menu.
///
/// They share one line when they fit, as on an iPad. Otherwise the target and
/// the menu share a line above the add button, and at the accessibility text
/// sizes each takes its own. The first two layouts keep the target and the menu at their
/// natural width, so the menu never gets squeezed into wrapping, including in
/// the middle of a rotation (SW-203). The stacked one is used even when it
/// doesn't fit, and at the largest text sizes the menu alone can be wider than
/// the row, so there both may wrap rather than run past its edge.
struct RecipeFragrancesHeaderRow<AddButton: View>: View {
    let model: RecipeFormViewModel
    @ViewBuilder let addButton: AddButton

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                addButton
                Spacer()
                targetLabel(keepsNaturalWidth: true)
                unitPicker(keepsNaturalWidth: true)
            }
            VStack(alignment: .leading) {
                HStack {
                    targetLabel(keepsNaturalWidth: true)
                    Spacer()
                    unitPicker(keepsNaturalWidth: true)
                }
                addButton
            }
            VStack(alignment: .leading) {
                addButton
                targetLabel(keepsNaturalWidth: false)
                unitPicker(keepsNaturalWidth: false)
            }
        }
    }

    @ViewBuilder
    private func targetLabel(keepsNaturalWidth: Bool) -> some View {
        if let target = model.fragranceTarget {
            HStack(spacing: 4) {
                Text(target.text)
                    .lineLimit(keepsNaturalWidth ? 1 : nil)
                    .foregroundStyle(target.isOverTarget ? Color.red : Color.secondary)
                InfoPopoverIcon(text: targetInfoText(for: target))
            }
        }
    }

    private func unitPicker(keepsNaturalWidth: Bool) -> some View {
        Picker("Unit", selection: Binding(
            get: { model.fragranceUnit },
            set: { model.setFragranceUnit($0) }
        )) {
            ForEach(model.availableFragranceUnits, id: \.self) { Text($0.rawValue) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize(horizontal: keepsNaturalWidth, vertical: keepsNaturalWidth)
    }

    private func targetInfoText(for target: FragranceTarget) -> String {
        let load = "Recommended fragrance load: "
            + "\(model.formatPercentage(target.percentage))% of total oils, "
            + "set on the Config tab."
        guard model.fragranceUnit == .percentOfFragrances else { return load }
        return load + " Each row is its share of that load; the shares should total 100%."
    }
}
