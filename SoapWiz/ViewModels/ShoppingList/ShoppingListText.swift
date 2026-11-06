import Foundation
import SwiftData

/// The shopping list as plain text, for sharing or copying.
enum ShoppingListText {
    /// Empty when nothing is left to buy.
    static func make(
        items: [ShoppingListItem],
        lastPurchases: [PersistentIdentifier: LastPurchase] = [:],
        boughtDates: [PersistentIdentifier: Date] = [:],
        currencyCode: String = AppSettings.regionCurrencyCode(),
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let pending = items.filter { !$0.isChecked && boughtDates[$0.persistentModelID] == nil }.sorted { $0.createdAt < $1.createdAt }
        guard !pending.isEmpty else { return "" }
        let body = pending.flatMap {
            lines(for: $0, lastPurchases: lastPurchases, currencyCode: currencyCode, locale: locale)
        }
        return ([String(localized: "Shopping list")] + body).joined(separator: "\n")
    }

    private static func lines(
        for item: ShoppingListItem,
        lastPurchases: [PersistentIdentifier: LastPurchase],
        currencyCode: String,
        locale: Locale
    ) -> [String] {
        var lines = [mainLine(for: item, locale: locale)]
        if let ingredient = item.ingredient,
           let details = lastPurchases[ingredient.persistentModelID]?.line(
               unit: ingredient.unit,
               currencyCode: currencyCode,
               locale: locale
           ) {
            lines.append("    - " + details)
        }
        return lines
    }

    private static func mainLine(for item: ShoppingListItem, locale: Locale) -> String {
        var text = "• " + item.name
        if let amount = item.amount {
            let number = amount.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
            text += ", " + (item.unit.isEmpty ? number : "\(number) \(item.unit)")
        }
        if !item.note.isEmpty {
            text += " (\(item.note))"
        }
        return text
    }
}
