import Foundation

/// Turns the data rows of a CSV file into import rows, given which column holds
/// which field.
///
/// Each mapped column is parsed as a whole, because the number and date parsers
/// vote on the decimal mark and the day/month order across a column rather than
/// guess cell by cell. A cell that can't be read becomes an issue on its row
/// rather than failing the import; an empty cell is never an issue.
nonisolated enum CSVInventoryRowBuilder {
    /// `dataRows` excludes the header. `firstSourceLine` is the 1-based file
    /// line of the first of them: 2 under a header row, 1 without one. Rows
    /// with no text in any cell are dropped, and a row shorter than the
    /// mapping reads its missing cells as empty.
    static func rows(
        from dataRows: [[String]],
        mapping: [Int: InventoryImportField],
        firstSourceLine: Int,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .current
    ) -> [InventoryImportRow] {
        let kept = dataRows.enumerated().filter { !isBlank($0.element) }
        guard !kept.isEmpty else { return [] }

        let columns = ParsedColumns(rows: kept.map(\.element), mapping: mapping, locale: locale, calendar: calendar)
        return kept.enumerated().map { position, entry in
            row(at: position, sourceLine: firstSourceLine + entry.offset, columns: columns)
        }
    }

    /// Whether no cell of `row` has text; whitespace-only cells count as blank.
    static func isBlank(_ row: [String]) -> Bool {
        !row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func row(at position: Int, sourceLine: Int, columns: ParsedColumns) -> InventoryImportRow {
        var issues: [InventoryImportIssue] = []
        let quantity = readQuantity(at: position, columns: columns, issues: &issues)
        let unit = readUnit(quantityUnit: quantity?.unit, at: position, columns: columns, issues: &issues)
        let totalPrice = readTotalPrice(quantity: quantity?.amount, at: position, columns: columns, issues: &issues)
        let purchaseDate = readDate(columns.purchaseDates, field: .purchaseDate, at: position, columns: columns, issues: &issues)
        let expiryDate = readDate(columns.expiryDates, field: .expiryDate, at: position, columns: columns, issues: &issues)

        return InventoryImportRow(
            sourceLine: sourceLine,
            name: columns.cell(of: .name, at: position),
            categoryName: columns.cell(of: .category, at: position).nilIfEmpty,
            unit: unit,
            quantity: quantity?.amount,
            totalPrice: totalPrice,
            supplier: columns.cell(of: .supplier, at: position).nilIfEmpty,
            purchaseDate: purchaseDate,
            expiryDate: expiryDate,
            issues: issues
        )
    }

    private static func readQuantity(
        at position: Int,
        columns: ParsedColumns,
        issues: inout [InventoryImportIssue]
    ) -> CSVQuantity? {
        let text = columns.cell(of: .quantity, at: position)
        guard !text.isEmpty else { return nil }
        if let parsed = columns.quantities[position] {
            return parsed
        }
        if let unknown = unknownUnitText(in: text) {
            issues.append(.unknownUnit(unknown))
        } else {
            issues.append(.invalidQuantity)
        }
        return nil
    }

    /// The row's unit: the one in the quantity cell, else the unit column's.
    /// Both present and different is a conflict, since neither is more likely
    /// to be the one the user meant.
    private static func readUnit(
        quantityUnit: IngredientUnit?,
        at position: Int,
        columns: ParsedColumns,
        issues: inout [InventoryImportIssue]
    ) -> IngredientUnit? {
        let text = columns.cell(of: .unit, at: position)
        guard !text.isEmpty else { return quantityUnit }
        guard let columnUnit = CSVUnitParser.unit(text) else {
            issues.append(.unknownUnit(text))
            return quantityUnit
        }
        if let quantityUnit, quantityUnit != columnUnit {
            let quantityText = columns.cell(of: .quantity, at: position)
            issues.append(.conflictingUnits(
                quantityUnit: unitSuffix(of: quantityText) ?? quantityUnit.rawValue,
                unitColumn: text
            ))
        }
        return quantityUnit ?? columnUnit
    }

    /// The total price if it is readable, else the unit price times the
    /// quantity. Every non-empty price cell that can't be read warns, even
    /// when the other one covers for it.
    private static func readTotalPrice(
        quantity: Double?,
        at position: Int,
        columns: ParsedColumns,
        issues: inout [InventoryImportIssue]
    ) -> Double? {
        let totalText = columns.cell(of: .totalPrice, at: position)
        let unitPriceText = columns.cell(of: .unitPrice, at: position)
        let total = columns.totalPrices[position]
        let unitPrice = columns.unitPrices[position]
        if !totalText.isEmpty, total == nil {
            issues.append(.unreadablePrice(totalText))
        }
        if !unitPriceText.isEmpty, unitPrice == nil {
            issues.append(.unreadablePrice(unitPriceText))
        }
        if let total { return total }
        guard let unitPrice, let quantity else { return nil }
        return unitPrice * quantity
    }

    private static func readDate(
        _ dates: [Date?],
        field: InventoryImportField,
        at position: Int,
        columns: ParsedColumns,
        issues: inout [InventoryImportIssue]
    ) -> Date? {
        let text = columns.cell(of: field, at: position)
        if !text.isEmpty, dates[position] == nil {
            issues.append(.unreadableDate(text))
        }
        return dates[position]
    }

    /// The text after the number in a quantity cell, when it is present and
    /// follows a number: "xyz" in "500 xyz", but nothing for "abc", which has
    /// no number to be a unit of.
    private static func unknownUnitText(in cell: String) -> String? {
        guard let split = cell.firstIndex(where: \.isLetter),
              !cell[..<split].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let unit = unitSuffix(of: cell) else { return nil }
        return CSVUnitParser.unit(unit) == nil ? unit : nil
    }

    private static func unitSuffix(of cell: String) -> String? {
        guard let split = cell.firstIndex(where: \.isLetter) else { return nil }
        return cell[split...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The trimmed cells of each mapped column, one entry per kept row, and the
/// numeric and date columns parsed as wholes.
private nonisolated struct ParsedColumns {
    let quantities: [CSVQuantity?]
    let totalPrices: [Double?]
    let unitPrices: [Double?]
    let purchaseDates: [Date?]
    let expiryDates: [Date?]
    private let cellsByField: [InventoryImportField: [String]]
    private let rowCount: Int

    init(rows: [[String]], mapping: [Int: InventoryImportField], locale: Locale, calendar: Calendar) {
        rowCount = rows.count
        var cellsByField: [InventoryImportField: [String]] = [:]
        for (index, field) in mapping.sorted(by: { $0.key < $1.key }) where cellsByField[field] == nil {
            cellsByField[field] = rows.map { row in
                row.indices.contains(index) ? row[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            }
        }
        self.cellsByField = cellsByField

        let empty = Array(repeating: "", count: rows.count)
        func cells(_ field: InventoryImportField) -> [String] { cellsByField[field] ?? empty }
        quantities = CSVUnitParser.quantities(in: cells(.quantity), locale: locale)
        totalPrices = CSVNumberParser.numbers(in: cells(.totalPrice), locale: locale)
        unitPrices = CSVNumberParser.numbers(in: cells(.unitPrice), locale: locale)
        purchaseDates = CSVDateParser.dates(in: cells(.purchaseDate), locale: locale, calendar: calendar)
        expiryDates = CSVDateParser.dates(in: cells(.expiryDate), locale: locale, calendar: calendar)
    }

    func cell(of field: InventoryImportField, at position: Int) -> String {
        cellsByField[field]?[position] ?? ""
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
