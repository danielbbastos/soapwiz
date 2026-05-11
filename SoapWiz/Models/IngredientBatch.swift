import Foundation
import SwiftData

@Model
final class IngredientBatch {
    var ingredient: Ingredient?
    var provider: String
    var dateOfPurchase: Date
    var quantity: Double
    var totalPrice: Double
    var badge: String
    var journalCode: String
    var expiryDate: Date?
    var openingDate: Date?
    var remainingAmount: Double
    var storageLocation: StorageLocation?

    var pricePerUnit: Double {
        guard quantity > 0 else { return 0 }
        return totalPrice / quantity
    }

    init(
        provider: String,
        dateOfPurchase: Date,
        quantity: Double,
        totalPrice: Double,
        badge: String,
        journalCode: String,
        expiryDate: Date?,
        openingDate: Date?,
        storageLocation: StorageLocation? = nil
    ) {
        self.provider = provider
        self.dateOfPurchase = dateOfPurchase
        self.quantity = quantity
        self.totalPrice = totalPrice
        self.badge = badge
        self.journalCode = journalCode
        self.expiryDate = expiryDate
        self.openingDate = openingDate
        self.remainingAmount = quantity
        self.storageLocation = storageLocation
    }
}
