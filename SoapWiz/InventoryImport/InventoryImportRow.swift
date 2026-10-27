import Foundation

/// One line of an inventory import, as its source read it: an ingredient and,
/// usually, a purchase of it.
///
/// Knows nothing about where it came from. A spreadsheet row and a line on an
/// invoice photo both become one of these, so the matcher, the review screen and
/// the applier serve every source.
nonisolated struct InventoryImportRow: Identifiable, Equatable {
    let id: UUID
    /// Where the row sat in its source, for pointing the user at it, when the
    /// source has such a position.
    let sourceLine: Int?
    var name: String
    var categoryName: String?
    /// `nil` when the source gave none: the quantity is then taken to be in the
    /// matched ingredient's own unit.
    var unit: IngredientUnit?
    var quantity: Double?
    /// What was paid for the whole quantity, not a price per unit.
    var totalPrice: Double?
    var supplier: String?
    var purchaseDate: Date?
    var expiryDate: Date?
    /// Problems the source found while reading the row.
    var issues: [InventoryImportIssue]

    init(
        id: UUID = UUID(),
        sourceLine: Int? = nil,
        name: String,
        categoryName: String? = nil,
        unit: IngredientUnit? = nil,
        quantity: Double? = nil,
        totalPrice: Double? = nil,
        supplier: String? = nil,
        purchaseDate: Date? = nil,
        expiryDate: Date? = nil,
        issues: [InventoryImportIssue] = []
    ) {
        self.id = id
        self.sourceLine = sourceLine
        self.name = name
        self.categoryName = categoryName
        self.unit = unit
        self.quantity = quantity
        self.totalPrice = totalPrice
        self.supplier = supplier
        self.purchaseDate = purchaseDate
        self.expiryDate = expiryDate
        self.issues = issues
    }
}
