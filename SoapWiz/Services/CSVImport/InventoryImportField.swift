import Foundation

/// What a spreadsheet column holds, as far as an inventory import is concerned.
///
/// A column is mapped to at most one field and a field to at most one column.
/// Headers are recognised by `lookupKey` equality with a list of names in
/// English, Portuguese, Spanish, French and German, so case, accents and
/// spacing don't matter. No two fields share a name: "amount" is a quantity,
/// and a price is "price" or "cost".
///
/// Each field's names are ranked, strongest first. When several columns name
/// the same field, the one matching the highest-ranked name wins, so "Name"
/// beats "Description" and "Total" beats "Price" whatever their order.
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
            ["name", "ingredient name", "ingredient",
             "nome", "ingrediente", "nombre", "nom", "ingrédient", "zutat", "bezeichnung",
             "product", "produto", "producto", "produit", "produkt", "material", "item", "artikel",
             "description"]
        case .category:
            ["category", "categoria", "categoría", "catégorie", "kategorie",
             "type", "tipo", "group"]
        case .quantity:
            ["quantity", "qty", "quantidade", "cantidad", "quantité", "menge",
             "amount", "stock", "weight", "peso", "gewicht"]
        case .unit:
            ["unit", "unit of measure", "uom", "unidade", "unidad", "unité", "einheit", "units"]
        case .totalPrice:
            ["total price", "total cost", "total", "amount paid",
             "preço total", "custo total", "valor total", "precio total", "coste total", "costo total",
             "importe", "prix total", "coût total", "montant", "gesamtpreis", "gesamtkosten", "betrag",
             "price", "cost", "preço", "preco", "custo", "precio", "coste", "costo", "prix", "coût",
             "preis", "kosten", "valor"]
        case .unitPrice:
            ["unit price", "price per unit", "cost per unit", "preço unitário", "precio unitario",
             "prix unitaire", "stückpreis", "einzelpreis",
             "preço por unidade", "custo unitário", "precio por unidad", "coste unitario",
             "prix par unité", "coût unitaire", "preis pro einheit"]
        case .supplier:
            ["supplier", "vendor", "fornecedor", "proveedor", "fournisseur", "lieferant",
             "provider", "store", "shop", "loja", "tienda"]
        case .purchaseDate:
            ["purchase date", "date purchased", "order date", "data de compra", "fecha de compra",
             "date d'achat", "kaufdatum",
             "date", "data", "fecha", "datum", "bought"]
        case .expiryDate:
            ["expiry date", "expiration date", "best before", "use by", "data de validade",
             "fecha de caducidad", "date d'expiration", "ablaufdatum",
             "expiry", "expiration", "validade", "caducidad", "péremption", "mhd"]
        }
    }

    private static let fieldsByHeaderKey: [String: (field: InventoryImportField, rank: Int)] = {
        var fields: [String: (field: InventoryImportField, rank: Int)] = [:]
        for field in allCases {
            for (rank, name) in field.headerNames.enumerated() where fields[name.lookupKey] == nil {
                fields[name.lookupKey] = (field, rank)
            }
        }
        return fields
    }()

    private static func match(forHeader header: String) -> (field: InventoryImportField, rank: Int)? {
        var key = header.lookupKey
        if key.hasSuffix(":") {
            key.removeLast()
            key = key.trimmingCharacters(in: .whitespaces)
        }
        return fieldsByHeaderKey[key]
    }

    /// The field `header` names, ignoring case, accents, spacing and a
    /// trailing ":".
    static func field(forHeader header: String) -> InventoryImportField? {
        match(forHeader: header)?.field
    }

    /// The field each column of `header` holds, by column index. A field goes
    /// to the column whose header matches its highest-ranked name, the leftmost
    /// of any that tie; the other columns naming it stay unmapped.
    static func detect(header: [String]) -> [Int: InventoryImportField] {
        var best: [InventoryImportField: (index: Int, rank: Int)] = [:]
        for (index, cell) in header.enumerated() {
            guard let match = match(forHeader: cell) else { continue }
            if let current = best[match.field], current.rank <= match.rank { continue }
            best[match.field] = (index, match.rank)
        }
        return Dictionary(uniqueKeysWithValues: best.map { ($0.value.index, $0.key) })
    }

    /// Whether `row` reads as a header: at least one cell names a field.
    static func isHeader(_ row: [String]) -> Bool {
        row.contains { field(forHeader: $0) != nil }
    }
}
