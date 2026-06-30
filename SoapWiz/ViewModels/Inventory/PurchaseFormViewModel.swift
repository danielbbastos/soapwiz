import Foundation
import SwiftData

@MainActor
@Observable
final class PurchaseFormViewModel {
    var selectedProvider: Provider?
    var dateOfPurchase: Date = Date()
    var quantityText: String = ""
    var totalPriceText: String = ""
    var badge: String = ""
    var journalCode: String = ""
    var hasExpiryDate: Bool = false
    /// Defaults to one year out; overwritten when editing a purchase that has an expiry.
    var expiryDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    var hasOpeningDate: Bool = false
    var openingDate: Date = Date()
    var selectedLocation: StorageLocation?

    let ingredient: Ingredient
    let purchase: IngredientPurchase?

    private struct Snapshot {
        let provider: Provider?
        let dateOfPurchase: Date
        let quantityText: String
        let totalPriceText: String
        let badge: String
        let journalCode: String
        let hasExpiryDate: Bool
        let expiryDate: Date
        let hasOpeningDate: Bool
        let openingDate: Date
        let location: StorageLocation?
    }

    private let initialSnapshot: Snapshot?

    init(ingredient: Ingredient, purchase: IngredientPurchase? = nil) {
        self.ingredient = ingredient
        self.purchase = purchase
        if let purchase {
            let qtyText = purchase.quantity.formatted(.number.precision(.fractionLength(0...2)))
            let priceText = purchase.totalPrice.formatted(.number.precision(.fractionLength(0...2)))
            let hasExpiry = purchase.expiryDate != nil
            let expiry = purchase.expiryDate ?? Calendar.current.date(
                byAdding: .year, value: 1, to: Date()
            ) ?? Date()
            let hasOpening = purchase.openingDate != nil
            let opening = purchase.openingDate ?? Date()

            selectedProvider = purchase.provider
            dateOfPurchase = purchase.dateOfPurchase
            quantityText = qtyText
            totalPriceText = priceText
            badge = purchase.badge
            journalCode = purchase.journalCode
            hasExpiryDate = hasExpiry
            expiryDate = expiry
            hasOpeningDate = hasOpening
            openingDate = opening
            selectedLocation = purchase.storageLocation

            initialSnapshot = Snapshot(
                provider: purchase.provider,
                dateOfPurchase: purchase.dateOfPurchase,
                quantityText: qtyText,
                totalPriceText: priceText,
                badge: purchase.badge,
                journalCode: purchase.journalCode,
                hasExpiryDate: hasExpiry,
                expiryDate: expiry,
                hasOpeningDate: hasOpening,
                openingDate: opening,
                location: purchase.storageLocation
            )
        } else {
            initialSnapshot = nil
        }
    }

    var isEditing: Bool { purchase != nil }
    var quantity: Double {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.number(from: quantityText)?.doubleValue ?? 0
    }

    var totalPrice: Double {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.number(from: totalPriceText)?.doubleValue ?? 0
    }
    var pricePerUnit: Double {
        guard quantity > 0 else { return 0 }
        return totalPrice / quantity
    }

    var isDirty: Bool {
        guard let snap = initialSnapshot else { return true }
        return selectedProvider !== snap.provider
            || dateOfPurchase != snap.dateOfPurchase
            || quantityText != snap.quantityText
            || totalPriceText != snap.totalPriceText
            || badge != snap.badge
            || journalCode != snap.journalCode
            || hasExpiryDate != snap.hasExpiryDate
            || (hasExpiryDate && expiryDate != snap.expiryDate)
            || hasOpeningDate != snap.hasOpeningDate
            || (hasOpeningDate && openingDate != snap.openingDate)
            || selectedLocation !== snap.location
    }

    var isValid: Bool { quantity > 0 && isDirty }

    func save(context: ModelContext) {
        if let purchase {
            purchase.provider = selectedProvider
            purchase.dateOfPurchase = dateOfPurchase
            purchase.quantity = quantity
            purchase.totalPrice = totalPrice
            purchase.badge = badge
            purchase.journalCode = journalCode
            purchase.expiryDate = hasExpiryDate ? expiryDate : nil
            purchase.openingDate = hasOpeningDate ? openingDate : nil
            purchase.storageLocation = selectedLocation
        } else {
            let newPurchase = IngredientPurchase(
                provider: selectedProvider,
                dateOfPurchase: dateOfPurchase,
                quantity: quantity,
                totalPrice: totalPrice,
                badge: badge,
                journalCode: journalCode,
                expiryDate: hasExpiryDate ? expiryDate : nil,
                openingDate: hasOpeningDate ? openingDate : nil,
                storageLocation: selectedLocation
            )
            context.insert(newPurchase)
            ingredient.purchases.append(newPurchase)
        }
    }
}
