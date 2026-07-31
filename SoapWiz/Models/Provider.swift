import Foundation
import SwiftData

@Model
final class Provider {
    /// Stable identity across devices, so a name collision arriving from CloudKit
    /// can be collapsed the same way everywhere. See `DuplicateMerger`.
    var uuid: UUID = UUID()
    var name: String = ""
    var website: String = ""
    var notes: String = ""

    /// Optional for CloudKit; read and write through `purchases`. Neither name is
    /// usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .nullify, originalName: "purchases", inverse: \IngredientPurchase.provider)
    var purchasesStorage: [IngredientPurchase]? = []

    var purchases: [IngredientPurchase] {
        get { purchasesStorage ?? [] }
        set { purchasesStorage = newValue }
    }

    init(name: String, website: String = "", notes: String = "") {
        self.name = name
        self.website = website
        self.notes = notes
    }
}
