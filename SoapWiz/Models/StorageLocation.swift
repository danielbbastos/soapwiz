import Foundation
import SwiftData

@Model
final class StorageLocation {
    var name: String
    var locationDescription: String

    @Relationship(deleteRule: .nullify, inverse: \IngredientPurchase.storageLocation)
    var purchases: [IngredientPurchase] = []

    init(name: String, locationDescription: String = "") {
        self.name = name
        self.locationDescription = locationDescription
    }
}
