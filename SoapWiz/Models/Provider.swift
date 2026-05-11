import Foundation
import SwiftData

@Model
final class Provider {
    var name: String
    var website: String
    var notes: String

    @Relationship(deleteRule: .nullify, inverse: \IngredientBatch.provider)
    var batches: [IngredientBatch] = []

    init(name: String, website: String = "", notes: String = "") {
        self.name = name
        self.website = website
        self.notes = notes
    }
}
