import Foundation
import SwiftData

@Model
final class StorageLocation {
    var name: String = ""
    var locationDescription: String = ""

    /// Optional for CloudKit; read and write through `purchases`. Neither name is
    /// usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .nullify, originalName: "purchases", inverse: \IngredientPurchase.storageLocation)
    var purchasesStorage: [IngredientPurchase]? = []

    var purchases: [IngredientPurchase] {
        get { purchasesStorage ?? [] }
        set { purchasesStorage = newValue }
    }

    init(name: String, locationDescription: String = "") {
        self.name = name
        self.locationDescription = locationDescription
    }
}
