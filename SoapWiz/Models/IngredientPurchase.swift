import Foundation
import SwiftData

@Model
final class IngredientPurchase {
    /// Stable identity for batch draw snapshots to point back at. Badges and
    /// journal codes are user-entered and can be empty or duplicated, so they
    /// can't serve as the link.
    var uuid: UUID = UUID()
    var ingredient: Ingredient?
    var provider: Provider?
    var dateOfPurchase: Date = Date.now
    var quantity: Double = 0
    var totalPrice: Double = 0
    var badge: String = ""
    var journalCode: String = ""
    var expiryDate: Date?
    var openingDate: Date?
    var remainingAmount: Double = 0
    var storageLocation: StorageLocation?

    var pricePerUnit: Double {
        guard quantity > 0 else { return 0 }
        return totalPrice / quantity
    }

    init(
        provider: Provider? = nil,
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
