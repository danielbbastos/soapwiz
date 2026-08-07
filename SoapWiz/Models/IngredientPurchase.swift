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

    /// Stamps the opening date the first time the purchase is drawn from. Never
    /// overwrites an existing date — the user may have opened it by hand earlier,
    /// and that record is the more accurate one. For callers that observe the
    /// draw itself, such as batch creation.
    func markOpened() {
        guard openingDate == nil else { return }
        openingDate = .now
    }

    /// Infers that the purchase has been opened from its remaining amount, for
    /// the inventory screen, which sees only the new stock level and has no draw
    /// event to observe. Not a substitute for `markOpened`: `remainingAmount` can
    /// exceed `quantity` when the quantity is edited down after some was used
    /// (`PurchaseFormViewModel.save` rewrites `quantity` alone), and this then
    /// infers nothing.
    func markOpenedIfPartlyUsed() {
        guard remainingAmount < quantity else { return }
        markOpened()
    }
}
