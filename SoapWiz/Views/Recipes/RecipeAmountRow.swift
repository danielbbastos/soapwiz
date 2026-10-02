import SwiftUI

/// An ingredient row in the recipe form: its name, its amount field and
/// whatever follows the amount, a unit label or menu.
///
/// The unit always shows in full and the name keeps the room it needs; the
/// amount field takes the rest, so it can be tapped anywhere between the name
/// and the unit, not only on the number itself. On a row too narrow for a long
/// name beside the field's minimum width, as on an iPhone, the name wraps onto
/// a second line rather than squeezing the unit.
struct RecipeAmountRow<Trailing: View>: View {
    let name: String
    @Binding var amount: Double
    var fractionLength: ClosedRange<Int> = 0...1
    var fieldWidth: CGFloat = 60
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            Text(name)
                .layoutPriority(1)
            NumericTextField(
                prompt: "0",
                value: $amount,
                fractionLength: fractionLength,
                width: fieldWidth,
                fillsAvailableWidth: true
            )
            trailing
                .fixedSize()
        }
    }
}
