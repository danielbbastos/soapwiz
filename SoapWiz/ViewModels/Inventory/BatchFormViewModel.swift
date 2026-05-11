import Foundation
import SwiftData

@MainActor
@Observable
final class BatchFormViewModel {
    var selectedProvider: Provider?
    var dateOfPurchase: Date = Date()
    var quantityText: String = ""
    var totalPriceText: String = ""
    var badge: String = ""
    var journalCode: String = ""
    var hasExpiryDate: Bool = false
    var expiryDate: Date = Date()
    var hasOpeningDate: Bool = false
    var openingDate: Date = Date()
    var selectedLocation: StorageLocation?

    let ingredient: Ingredient
    let batch: IngredientBatch?

    init(ingredient: Ingredient, batch: IngredientBatch? = nil) {
        self.ingredient = ingredient
        self.batch = batch
        if let batch {
            selectedProvider = batch.provider
            dateOfPurchase = batch.dateOfPurchase
            quantityText = batch.quantity.formatted(.number.precision(.fractionLength(0...2)))
            totalPriceText = batch.totalPrice.formatted(.number.precision(.fractionLength(0...2)))
            badge = batch.badge
            journalCode = batch.journalCode
            if let expiry = batch.expiryDate {
                hasExpiryDate = true
                expiryDate = expiry
            }
            if let opening = batch.openingDate {
                hasOpeningDate = true
                openingDate = opening
            }
            selectedLocation = batch.storageLocation
        }
    }

    var isEditing: Bool { batch != nil }
    var quantity: Double { Double(quantityText) ?? 0 }
    var totalPrice: Double { Double(totalPriceText) ?? 0 }
    var pricePerUnit: Double {
        guard quantity > 0 else { return 0 }
        return totalPrice / quantity
    }
    var isValid: Bool { quantity > 0 }

    func save(context: ModelContext) {
        if let batch {
            batch.provider = selectedProvider
            batch.dateOfPurchase = dateOfPurchase
            batch.quantity = quantity
            batch.totalPrice = totalPrice
            batch.badge = badge
            batch.journalCode = journalCode
            batch.expiryDate = hasExpiryDate ? expiryDate : nil
            batch.openingDate = hasOpeningDate ? openingDate : nil
            batch.storageLocation = selectedLocation
        } else {
            let newBatch = IngredientBatch(
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
            context.insert(newBatch)
            ingredient.batches.append(newBatch)
        }
    }
}
