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

    init(ingredient: Ingredient, purchase: IngredientPurchase? = nil) {
        self.ingredient = ingredient
        self.purchase = purchase
        if let purchase {
            selectedProvider = purchase.provider
            dateOfPurchase = purchase.dateOfPurchase
            quantityText = purchase.quantity.formatted(.number.precision(.fractionLength(0...2)))
            totalPriceText = purchase.totalPrice.formatted(.number.precision(.fractionLength(0...2)))
            badge = purchase.badge
            journalCode = purchase.journalCode
            if let expiry = purchase.expiryDate {
                hasExpiryDate = true
                expiryDate = expiry
            }
            if let opening = purchase.openingDate {
                hasOpeningDate = true
                openingDate = opening
            }
            selectedLocation = purchase.storageLocation
        }
    }

    var isEditing: Bool { purchase != nil }
    var quantity: Double { Double(quantityText) ?? 0 }
    var totalPrice: Double { Double(totalPriceText) ?? 0 }
    var pricePerUnit: Double {
        guard quantity > 0 else { return 0 }
        return totalPrice / quantity
    }
    var isValid: Bool { quantity > 0 }

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
