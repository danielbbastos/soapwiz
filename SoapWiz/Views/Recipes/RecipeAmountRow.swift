import SwiftUI

/// An ingredient row in the recipe form: its name, its amount field and
/// whatever follows the amount, a unit label or menu.
///
/// The unit always shows in full and the name keeps the room it needs; the
/// amount field takes the rest, so it can be tapped anywhere between the name
/// and the unit, not only on the number itself. On a row too narrow for a long
/// name beside the field's minimum width, as on an iPhone, the name wraps onto
/// a second line rather than squeezing the unit. At the accessibility text
/// sizes the name, the amount and the unit each take their own line, since
/// the unit alone can be about as wide as the row.
struct RecipeAmountRow<Trailing: View>: View {
    let name: String
    @Binding var amount: Double
    var fractionLength: ClosedRange<Int> = 0...1
    var fieldWidth: CGFloat = 60
    @ViewBuilder let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                Text(name)
                amountField(alignment: .leading)
                trailing
            }
        } else {
            HStack {
                Text(name)
                    .layoutPriority(1)
                amountField(alignment: .trailing)
                trailing
                    .fixedSize()
            }
        }
    }

    private func amountField(alignment: TextAlignment) -> some View {
        NumericTextField(
            prompt: "0",
            value: $amount,
            fractionLength: fractionLength,
            width: fieldWidth,
            fillsAvailableWidth: true,
            alignment: alignment
        )
    }
}
