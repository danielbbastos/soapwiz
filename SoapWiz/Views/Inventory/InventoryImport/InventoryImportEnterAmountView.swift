import SwiftUI

/// Lets the user type the amount of a row blocked only by its unit, in the
/// ingredient's own unit. The field always starts empty: SoapWiz never guesses
/// the conversion, so there is nothing it could honestly pre-fill.
///
/// The blocked row shows this in place of its "Enter amount" button, and drops it by
/// clearing `isEntering`. The text lives here, so a row that comes back after an
/// undo always opens with an empty field.
///
/// At accessibility text sizes the buttons move onto their own lines.
struct InventoryImportEnterAmountView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let model: InventoryImportReviewViewModel
    let line: InventoryImportLine
    let unit: String
    var onClose: () -> Void

    @State private var text = ""

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16))
    }

    private var isValid: Bool {
        model.parsedAmount(text) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color.rule)
                .frame(height: 1)
                .accessibilityHidden(true)
            HoneyLedgerField("Amount", unit: unit) { focus in
                HoneyLedgerTextInput(title: "Amount", text: $text, prompt: "0", keyboard: .decimalPad, focus: focus)
                    .onAppear { focus.wrappedValue = true }
            }
            if let note = model.fileQuantityNote(line) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
            layout {
                InventoryImportRowButton("Confirm", color: isValid ? .amberText : .inkFaint) {
                    let typed = text
                    InventoryImportMotion.animate {
                        onClose()
                        model.enterAmount(typed, line: line.id)
                    }
                }
                .disabled(!isValid)
                InventoryImportRowButton("Cancel", color: .inkSoft, action: onClose)
            }
        }
    }
}
