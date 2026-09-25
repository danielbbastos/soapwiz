import Foundation

/// One entry in the Settings currency picker.
struct CurrencyChoice: Identifiable, Hashable {
    let code: String
    let label: String
    var id: String { code }

    /// Every common currency, labelled "Euro (EUR)" in the user's language and
    /// sorted by that label. `selected` is always offered, even when it isn't a
    /// common code, so a synced choice never leaves the picker without a match.
    static func all(including selected: String, locale: Locale = .autoupdatingCurrent) -> [CurrencyChoice] {
        Set(Locale.commonISOCurrencyCodes + [selected])
            .filter { !$0.isEmpty }
            .map { code in
                let name = locale.localizedString(forCurrencyCode: code) ?? code
                return CurrencyChoice(code: code, label: "\(name) (\(code))")
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
}
