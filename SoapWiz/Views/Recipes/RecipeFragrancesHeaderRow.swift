import SwiftUI

/// The first row of the recipe form's Fragrances section: the add button, the
/// fragrance target and the unit menu.
///
/// They share one line when they fit, as on an iPad. Otherwise the target and
/// the menu move to a second line, and at the accessibility text sizes each
/// takes its own. Every layout is measured at its natural width, so the menu
/// never gets squeezed into wrapping, including in the middle of a rotation
/// (SW-203).
struct RecipeFragrancesHeaderRow<AddButton: View>: View {
    let model: RecipeFormViewModel
    @ViewBuilder let addButton: AddButton

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                addButton
                Spacer()
                targetLabel
                unitPicker
            }
            VStack(alignment: .leading) {
                addButton
                HStack {
                    targetLabel
                    Spacer()
                    unitPicker
                }
            }
            VStack(alignment: .leading) {
                addButton
                targetLabel
                unitPicker
            }
        }
    }

    @ViewBuilder
    private var targetLabel: some View {
        if let target = model.fragranceTarget {
            HStack(spacing: 4) {
                Text(target.text)
                    .lineLimit(1)
                    .foregroundStyle(target.isOverTarget ? Color.red : Color.secondary)
                InfoPopoverIcon(text: targetInfoText(for: target))
            }
        }
    }

    private var unitPicker: some View {
        Picker("Unit", selection: Binding(
            get: { model.fragranceUnit },
            set: { model.setFragranceUnit($0) }
        )) {
            ForEach(model.availableFragranceUnits, id: \.self) { Text($0.rawValue) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private func targetInfoText(for target: FragranceTarget) -> String {
        let load = "Recommended fragrance load: "
            + "\(model.formatPercentage(target.percentage))% of total oils, "
            + "set on the Config tab."
        guard model.fragranceUnit == .percentOfFragrances else { return load }
        return load + " Each row is its share of that load; the shares should total 100%."
    }
}
