import Testing
@testable import SoapWiz

@Suite
struct InventoryImportFieldTests {
    @Test(arguments: [
        ("Name", InventoryImportField.name), ("Ingredient", .name), ("Nome", .name), ("Nombre", .name),
        ("Zutat", .name), ("Ingrédient", .name),
        ("Category", .category), ("Categoría", .category), ("Kategorie", .category),
        ("Quantity", .quantity), ("Qty", .quantity), ("Amount", .quantity), ("Quantidade", .quantity),
        ("Cantidad", .quantity), ("Quantité", .quantity), ("Menge", .quantity),
        ("Unit", .unit), ("Unidade", .unit), ("Unité", .unit), ("Einheit", .unit),
        ("Price", .totalPrice), ("Total cost", .totalPrice), ("Preço", .totalPrice), ("Precio", .totalPrice),
        ("Coût", .totalPrice), ("Preis", .totalPrice),
        ("Unit price", .unitPrice), ("Preço unitário", .unitPrice), ("Stückpreis", .unitPrice),
        ("Supplier", .supplier), ("Fornecedor", .supplier), ("Proveedor", .supplier), ("Lieferant", .supplier),
        ("Purchase date", .purchaseDate), ("Data de compra", .purchaseDate), ("Fecha", .purchaseDate),
        ("Kaufdatum", .purchaseDate),
        ("Expiry date", .expiryDate), ("Best before", .expiryDate), ("Validade", .expiryDate),
        ("Péremption", .expiryDate), ("MHD", .expiryDate)
    ])
    func field_Synonym_ReturnsField(header: String, expected: InventoryImportField) {
        #expect(InventoryImportField.field(forHeader: header) == expected)
    }

    @Test(arguments: ["  NAME ", "preco", "PRECO", "ingredient   name", "Name:", "Unit Price :"])
    func field_CaseAccentSpacingAndColon_AreFolded(header: String) {
        #expect(InventoryImportField.field(forHeader: header) != nil)
    }

    @Test func field_UnknownHeader_ReturnsNil() {
        #expect(InventoryImportField.field(forHeader: "Shelf") == nil)
        #expect(InventoryImportField.field(forHeader: "") == nil)
    }

    @Test func field_Amount_IsQuantityNotPrice() {
        #expect(InventoryImportField.field(forHeader: "amount") == .quantity)
    }

    @Test func detect_MapsColumnsByIndex() {
        let mapping = InventoryImportField.detect(header: ["Name", "Shelf", "Qty", "Unit"])

        #expect(mapping == [0: .name, 2: .quantity, 3: .unit])
    }

    @Test func detect_DuplicateHeader_FirstColumnWins() {
        let mapping = InventoryImportField.detect(header: ["Name", "Item", "Product"])

        #expect(mapping == [0: .name])
    }

    @Test func detect_StrongerSynonymLater_BeatsWeakerEarlier() {
        let mapping = InventoryImportField.detect(header: ["Description", "Name"])

        #expect(mapping == [1: .name])
    }

    @Test func detect_TotalAfterPrice_TotalGetsTotalPrice() {
        let mapping = InventoryImportField.detect(header: ["Price", "Total"])

        #expect(mapping == [1: .totalPrice])
    }

    @Test func detect_PurchaseDateAfterDate_PurchaseDateWins() {
        let mapping = InventoryImportField.detect(header: ["Date", "Purchase Date"])

        #expect(mapping == [1: .purchaseDate])
    }

    @Test func detect_EqualRankDuplicates_LeftmostWins() {
        let mapping = InventoryImportField.detect(header: ["Qty", "Shelf", "qty"])

        #expect(mapping == [0: .quantity])
    }

    @Test(arguments: ["Preço total", "Precio total", "Prix total", "Gesamtpreis", "Valor total", "Montant"])
    func field_LocalizedTotalPrice_IsTotalPrice(header: String) {
        #expect(InventoryImportField.field(forHeader: header) == .totalPrice)
    }

    @Test(arguments: ["Preço por unidade", "Precio por unidad", "Prix par unité", "Preis pro Einheit", "Custo unitário"])
    func field_LocalizedUnitPrice_IsUnitPrice(header: String) {
        #expect(InventoryImportField.field(forHeader: header) == .unitPrice)
    }

    @Test func detect_PortugueseTotalAndUnitPrice_MapsBothColumns() {
        let mapping = InventoryImportField.detect(header: ["Nome", "Quantidade", "Preço total", "Preço unitário"])

        #expect(mapping[2] == .totalPrice)
        #expect(mapping[3] == .unitPrice)
    }

    @Test func detect_NoRecognisedHeader_ReturnsEmpty() {
        #expect(InventoryImportField.detect(header: ["Foo", "Bar"]).isEmpty)
        #expect(InventoryImportField.detect(header: []).isEmpty)
    }

    @Test func isHeader_RowNamingAField_IsTrue() {
        #expect(InventoryImportField.isHeader(["Ingredient", "???", "Qty"]))
    }

    @Test func isHeader_DataRow_IsFalse() {
        #expect(!InventoryImportField.isHeader(["Olive oil", "500", "12.5"]))
    }

    @Test func isHeader_EmptyRow_IsFalse() {
        #expect(!InventoryImportField.isHeader([]))
    }

    @Test func label_EveryField_IsNotEmpty() {
        for field in InventoryImportField.allCases {
            #expect(!field.label.isEmpty)
        }
    }
}
