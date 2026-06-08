import Foundation
import SwiftData

@Model
final class Provider {
    var name: String
    var website: String
    var notes: String

    @Relationship(deleteRule: .nullify, inverse: \IngredientPurchase.provider)
    var purchases: [IngredientPurchase] = []

    init(name: String, website: String = "", notes: String = "") {
        self.name = name
        self.website = website
        self.notes = notes
    }
}
