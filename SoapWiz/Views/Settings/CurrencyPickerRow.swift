import SwiftUI

/// Its own view so the currency list — every common currency, named and
/// sorted — is only rebuilt when the currency changes, not on every redraw of
/// Settings (each keystroke in the RRP factor field is one).
struct CurrencyPickerRow: View {
    @Environment(\.currencyCode) private var currencyCode
    let settings: AppSettings

    var body: some View {
        Picker("Currency", selection: Binding(
            get: { currencyCode },
            set: { settings.currencyCode = $0 }
        )) {
            ForEach(CurrencyChoice.all(including: currencyCode)) { choice in
                Text(choice.label).tag(choice.code)
            }
        }
        .pickerStyle(.navigationLink)
    }
}
