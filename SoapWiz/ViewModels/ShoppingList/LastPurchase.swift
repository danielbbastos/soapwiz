import Foundation
import SwiftData

/// What the shopping list says about where an ingredient was last bought.
struct LastPurchase: Equatable {
    let quantity: Double?
    let supplierName: String?
    let pricePerUnit: Double?

    init(quantity: Double?, supplierName: String?, pricePerUnit: Double?) {
        self.quantity = quantity
        self.supplierName = supplierName
        self.pricePerUnit = pricePerUnit
    }

    init(_ purchase: IngredientPurchase) {
        let name = purchase.provider?.name
        let pricePerUnit = purchase.pricePerUnit
        self.init(
            quantity: purchase.quantity > 0 ? purchase.quantity : nil,
            supplierName: name?.isEmpty == false ? name : nil,
            pricePerUnit: pricePerUnit == 0 ? nil : pricePerUnit
        )
    }

    /// The newest purchase of each ingredient, from one pass over `purchases`.
    static func newest(in purchases: [IngredientPurchase]) -> [PersistentIdentifier: LastPurchase] {
        var latest: [PersistentIdentifier: IngredientPurchase] = [:]
        for purchase in purchases {
            guard let id = purchase.ingredient?.persistentModelID else { continue }
            if let current = latest[id], current.dateOfPurchase >= purchase.dateOfPurchase { continue }
            latest[id] = purchase
        }
        return latest.mapValues(LastPurchase.init)
    }

    func line(unit: String, currencyCode: String, locale: Locale = .autoupdatingCurrent) -> String? {
        var parts: [String] = []
        if let quantity {
            let number = quantity.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
            let quantityText = unit.isEmpty ? number : "\(number) \(unit)"
            parts.append(String(localized: "Last purchase: \(quantityText)"))
        }
        if let supplierName {
            parts.append(supplierName)
        }
        if let pricePerUnit {
            let formatted = pricePerUnit.unitPriceFormatted(currencyCode: currencyCode, locale: locale)
            parts.append(unit.isEmpty ? formatted : "\(formatted) / \(unit)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
