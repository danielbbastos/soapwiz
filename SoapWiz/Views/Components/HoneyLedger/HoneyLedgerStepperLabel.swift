import SwiftUI

/// The label of a stepper on a ledger sheet: the title in `ink` on the leading
/// edge and the current value after it, in monospaced digits. `valueColor` is
/// `ink` for the figure the sheet is about and `inkSoft` for a setting.
struct HoneyLedgerStepperLabel: View {
    let title: LocalizedStringKey
    let value: Text
    let valueColor: Color

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.ink)
            Spacer(minLength: 8)
            value
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
    }
}
