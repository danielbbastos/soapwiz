import SwiftUI

/// Its own view so the currency list — every common currency, named and
/// sorted — is only rebuilt when the currency changes, not on every redraw of
/// Settings (each keystroke in the RRP factor field is one).
struct CurrencyPickerRow: View {
    @Environment(\.currencyCode) private var currencyCode
    let settings: AppSettings

    var body: some View {
        let current = CurrencyChoice.all(including: currencyCode).first { $0.code == currencyCode }
        NavigationLink {
            CurrencyListView(settings: settings)
        } label: {
            HoneyLedgerLabeledRow("Currency") {
                Text(current?.label ?? currencyCode)
                    .foregroundStyle(Color.inkSoft)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
