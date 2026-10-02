import SwiftUI

/// An ingredient row in the recipe form: its name, its amount field and
/// whatever follows the amount, a unit label or menu. A tap anywhere on the
/// row focuses the amount, so the field isn't only reachable through its own
/// narrow frame. A control in `trailing`, like the unit menu, still takes its
/// own taps.
struct RecipeAmountRow<Trailing: View>: View {
    let name: String
    @Binding var amount: Double
    var fractionLength: ClosedRange<Int> = 0...1
    var fieldWidth: CGFloat = 60
    @ViewBuilder let trailing: Trailing

    @FocusState private var isAmountFocused: Bool

    var body: some View {
        HStack {
            Text(name)
                .lineLimit(1)
            Spacer()
            NumericTextField(
                prompt: "0",
                value: $amount,
                fractionLength: fractionLength,
                width: fieldWidth,
                focus: $isAmountFocused
            )
            trailing
        }
        .contentShape(Rectangle())
        .onTapGesture { isAmountFocused = true }
    }
}
