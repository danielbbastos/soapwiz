import SwiftUI

/// A borderless input row: the label on the leading edge and the value on the
/// trailing edge, with an optional unit after it. While the field has focus the
/// label turns `amberText` semibold; the caret is the system's own, tinted
/// `amber`. An error turns the value `danger` and adds a caution line under the
/// row. At accessibility text sizes the value moves under the label.
///
/// `field` receives the focus binding, so it can be any text field that takes
/// one, a `NumericTextField` included.
struct HoneyLedgerField<Field: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    var unit: String?
    var error: String?
    let field: (FocusState<Bool>.Binding) -> Field

    @FocusState private var isFocused: Bool

    init(
        _ title: String,
        unit: String? = nil,
        error: String? = nil,
        @ViewBuilder field: @escaping (FocusState<Bool>.Binding) -> Field
    ) {
        self.title = title
        self.unit = unit
        self.error = error
        self.field = field
    }

    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    private var label: some View {
        Text(title)
            .font(.body.weight(isFocused ? .semibold : .regular))
            .foregroundStyle(isFocused ? Color.amberText : Color.ink)
            // The field carries the title for VoiceOver.
            .accessibilityHidden(true)
    }

    private var value: some View {
        HStack(spacing: 6) {
            field($isFocused)
                .font(.body.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(error == nil ? Color.ink : Color.danger)
                .tint(Color.amber)
                .multilineTextAlignment(isStacked ? .leading : .trailing)
                .frame(maxWidth: .infinity, alignment: isStacked ? .leading : .trailing)
            if let unit, !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(Color.inkSoft)
                    .fixedSize()
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isStacked {
                VStack(alignment: .leading, spacing: 4) {
                    label
                    value
                }
            } else {
                HStack(spacing: 16) {
                    label
                        .layoutPriority(1)
                    value
                }
            }
            if let error {
                HoneyLedgerFieldNote(error, tint: .danger)
            }
        }
        .animation(.default, value: isFocused)
    }
}

extension HoneyLedgerField where Field == HoneyLedgerTextInput {
    /// A plain text field. `prompt` is the placeholder, drawn in `inkFaint`.
    init(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        unit: String? = nil,
        error: String? = nil,
        keyboard: UIKeyboardType = .default
    ) {
        self.init(title, unit: unit, error: error) { focus in
            HoneyLedgerTextInput(title: title, text: text, prompt: prompt, keyboard: keyboard, focus: focus)
        }
    }
}

/// The text field inside a `HoneyLedgerField`.
struct HoneyLedgerTextInput: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let keyboard: UIKeyboardType
    let focus: FocusState<Bool>.Binding

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt).foregroundStyle(Color.inkFaint))
            .keyboardType(keyboard)
            .focused(focus)
    }
}

/// One sentence under a field, after a caution glyph, in `tint`.
struct HoneyLedgerFieldNote: View {
    let message: String
    let tint: Color

    init(_ message: String, tint: Color) {
        self.message = message
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
        }
        .font(.footnote)
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
    }
}

/// A value the form works out rather than takes: label and value in
/// `inkFaint`, not focusable.
struct HoneyLedgerCalculatedRow: View {
    let title: String
    let value: String

    var body: some View {
        HoneyLedgerLabeledRow(title, titleColor: .inkFaint) {
            Text.honeyLedgerFigure(value, numberColor: .inkFaint)
        }
    }
}
