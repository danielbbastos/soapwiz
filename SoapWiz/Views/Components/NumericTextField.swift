import SwiftUI

/// A decimal-pad field for a `Double`, which selects its whole value whenever it
/// gains focus so the next keystroke replaces the number instead of appending to
/// it. Pass `focus` to drive the field programmatically from the caller.
///
/// `width` is the field's width, or its minimum when `fillsAvailableWidth` is
/// set: the field then grows into whatever room its row leaves, so a tap
/// anywhere in that room lands on it.
struct NumericTextField: View {
    let prompt: String
    @Binding var value: Double
    var fractionLength: ClosedRange<Int> = 0...1
    var width: CGFloat = 60
    var fillsAvailableWidth = false
    var alignment: TextAlignment = .trailing
    var allowsDecimals = true
    var focus: FocusState<Bool>.Binding?

    @FocusState private var internalFocus: Bool

    private var isFocused: Bool { focus?.wrappedValue ?? internalFocus }

    var body: some View {
        TextField(
            prompt, value: $value,
            format: .number.precision(.fractionLength(allowsDecimals ? fractionLength : 0...0))
        )
            .keyboardType(allowsDecimals ? .decimalPad : .numberPad)
            .multilineTextAlignment(alignment)
            .onChange(of: value) { _, newValue in
                // The number pad has no separator, but a pasted "1.5" still parses.
                if !allowsDecimals, newValue != newValue.rounded(.down) {
                    value = newValue.rounded(.down)
                }
            }
            .frame(minWidth: width, maxWidth: fillsAvailableWidth ? .infinity : width)
            .focused(focus ?? $internalFocus)
            .onChange(of: isFocused) { _, focused in
                guard focused else { return }
                Task {
                    // SwiftUI makes the field first responder after it applies the
                    // focus change, so the selection has to wait for that to land.
                    await Task.yield()
                    // The action goes to whatever is first responder now, so bail
                    // if focus has already moved on — otherwise a fast second tap
                    // would have its own field selected out from under it.
                    guard isFocused else { return }
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil
                    )
                }
            }
    }
}
