import SwiftUI

/// An ingredient row in the recipe form: its name, its amount field and
/// whatever follows the amount, a unit label or menu. The name keeps the room
/// it needs and the amount field takes the rest, so the field can be tapped
/// anywhere between the name and the unit, not only on the number itself.
struct RecipeAmountRow<Trailing: View>: View {
    let name: String
    @Binding var amount: Double
    var fractionLength: ClosedRange<Int> = 0...1
    var fieldWidth: CGFloat = 60
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            Text(name)
                .lineLimit(1)
                .layoutPriority(1)
            NumericTextField(
                prompt: "0",
                value: $amount,
                fractionLength: fractionLength,
                width: fieldWidth,
                fillsAvailableWidth: true
            )
            trailing
        }
    }
}
