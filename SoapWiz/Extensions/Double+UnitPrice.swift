import Foundation

extension Double {
    /// A price per g, ml or other unit: cheap ingredients cost fractions of a
    /// cent per unit, so this keeps up to 4 decimals where totals keep 2.
    func unitPriceFormatted(currencyCode: String, locale: Locale = .current) -> String {
        formatted(.currency(code: currencyCode).precision(.fractionLength(2...4)).locale(locale))
    }
}
