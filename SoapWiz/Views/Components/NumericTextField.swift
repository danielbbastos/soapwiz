import SwiftUI

/// A decimal-pad field for a `Double`, which selects its whole value whenever it
/// gains focus so the next keystroke replaces the number instead of appending to
/// it. Pass `focus` to drive the field programmatically from the caller.
struct NumericTextField: View {
    let prompt: String
    @Binding var value: Double
    var fractionLength: ClosedRange<Int> = 0...1
    var width: CGFloat = 60
    var alignment: TextAlignment = .trailing
    var focus: FocusState<Bool>.Binding?

    @FocusState private var internalFocus: Bool

    private var isFocused: Bool { focus?.wrappedValue ?? internalFocus }

    var body: some View {
        TextField(prompt, value: $value, format: .number.precision(.fractionLength(fractionLength)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(alignment)
            .frame(width: width)
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
