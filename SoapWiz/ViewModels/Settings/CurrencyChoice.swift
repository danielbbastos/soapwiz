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

    /// The choices whose label or code contains `query`, ignoring case and
    /// diacritics. A blank query keeps every choice.
    static func filter(_ choices: [CurrencyChoice], matching query: String) -> [CurrencyChoice] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return choices }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return choices.filter {
            $0.label.range(of: trimmed, options: options) != nil
                || $0.code.range(of: trimmed, options: options) != nil
        }
    }
}
