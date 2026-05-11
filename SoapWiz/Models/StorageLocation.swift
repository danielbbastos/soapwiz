import Foundation
import SwiftData

@Model
final class StorageLocation {
    var name: String
    var locationDescription: String

    @Relationship(deleteRule: .nullify, inverse: \IngredientBatch.storageLocation)
    var batches: [IngredientBatch] = []

    init(name: String, locationDescription: String = "") {
        self.name = name
        self.locationDescription = locationDescription
    }
}
