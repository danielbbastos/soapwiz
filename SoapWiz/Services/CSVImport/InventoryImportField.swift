import Foundation

/// What a spreadsheet column holds, as far as an inventory import is concerned.
///
/// A column is mapped to at most one field and a field to at most one column.
/// Headers are recognised by `lookupKey` equality with a list of names in
/// English, Portuguese, Spanish, French and German, so case, accents and
/// spacing don't matter. No two fields share a name: "amount" is a quantity,
/// and a price is "price" or "cost".
nonisolated enum InventoryImportField: CaseIterable, Hashable {
    case name
    case category
    case quantity
    case unit
    /// What was paid for the whole quantity.
    case totalPrice
    /// What was paid for one unit of the quantity.
    case unitPrice
    case supplier
    case purchaseDate
    case expiryDate

    var label: String {
        switch self {
        case .name: String(localized: "Name")
        case .category: String(localized: "Category")
        case .quantity: String(localized: "Quantity")
        case .unit: String(localized: "Unit")
        case .totalPrice: String(localized: "Total price")
        case .unitPrice: String(localized: "Price per unit")
        case .supplier: String(localized: "Supplier")
        case .purchaseDate: String(localized: "Purchase date")
        case .expiryDate: String(localized: "Expiry date")
        }
    }

    private var headerNames: [String] {
        switch self {
        case .name:
            ["name", "ingredient", "ingredient name", "item", "product", "material", "description",
             "nome", "ingrediente", "produto", "nombre", "producto", "nom", "ingrédient", "produit",
             "zutat", "artikel", "produkt", "bezeichnung"]
        case .category:
            ["category", "type", "group", "categoria", "tipo", "categoría", "catégorie", "kategorie"]
        case .quantity:
            ["quantity", "qty", "amount", "stock", "weight", "quantidade", "peso", "cantidad",
             "quantité", "menge", "gewicht"]
        case .unit:
            ["unit", "units", "uom", "unit of measure", "unidade", "unidad", "unité", "einheit"]
        case .totalPrice:
            ["price", "total", "total price", "cost", "total cost", "amount paid", "preço", "preco",
             "custo", "valor", "precio", "coste", "costo", "prix", "coût", "preis", "kosten"]
        case .unitPrice:
            ["unit price", "price per unit", "cost per unit", "preço unitário", "precio unitario",
             "prix unitaire", "stückpreis", "einzelpreis"]
        case .supplier:
            ["supplier", "vendor", "provider", "store", "shop", "fornecedor", "loja", "proveedor",
             "tienda", "fournisseur", "lieferant"]
        case .purchaseDate:
            ["purchase date", "date", "bought", "date purchased", "order date", "data", "data de compra",
             "fecha", "fecha de compra", "date d'achat", "kaufdatum", "datum"]
        case .expiryDate:
            ["expiry", "expiry date", "expiration", "expiration date", "best before", "use by", "validade",
             "data de validade", "caducidad", "fecha de caducidad", "date d'expiration", "péremption",
             "ablaufdatum", "mhd"]
        }
    }

    private static let fieldsByHeaderKey: [String: InventoryImportField] = {
        var fields: [String: InventoryImportField] = [:]
        for field in allCases {
            for name in field.headerNames {
                fields[name.lookupKey] = fields[name.lookupKey] ?? field
            }
        }
        return fields
    }()

    /// The field `header` names, ignoring case, accents, spacing and a
    /// trailing ":".
    static func field(forHeader header: String) -> InventoryImportField? {
        var key = header.lookupKey
        if key.hasSuffix(":") {
            key.removeLast()
            key = key.trimmingCharacters(in: .whitespaces)
        }
        return fieldsByHeaderKey[key]
    }

    /// The field each column of `header` holds, by column index. A field goes
    /// to the first column that names it; later columns naming it stay unmapped.
    static func detect(header: [String]) -> [Int: InventoryImportField] {
        var mapping: [Int: InventoryImportField] = [:]
        var taken: Set<InventoryImportField> = []
        for (index, cell) in header.enumerated() {
            guard let field = field(forHeader: cell), taken.insert(field).inserted else { continue }
            mapping[index] = field
        }
        return mapping
    }

    /// Whether `row` reads as a header: at least one cell names a field.
    static func isHeader(_ row: [String]) -> Bool {
        row.contains { field(forHeader: $0) != nil }
    }
}
