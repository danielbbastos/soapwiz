import SwiftUI

extension Binding where Value == String {
    /// Drops anything that can't be part of a number, but keeps the separators
    /// as typed: reading them in the user's locale is `LocaleDecimal`'s job.
    func decimalOnly(locale: Locale = .autoupdatingCurrent) -> Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                let localeSeparators = [locale.groupingSeparator, locale.decimalSeparator].compactMap(\.self)
                wrappedValue = newValue.filter {
                    $0.isNumber || $0 == "." || $0 == "," || localeSeparators.contains(String($0))
                }
            }
        )
    }
}
