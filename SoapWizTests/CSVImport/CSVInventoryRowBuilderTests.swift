import Foundation
import Testing
@testable import SoapWiz

@Suite
struct CSVInventoryRowBuilderTests {
    private let american = Locale(identifier: "en_US")
    private let portuguese = Locale(identifier: "pt_PT")
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private func build(
        _ rows: [[String]],
        _ mapping: [Int: InventoryImportField],
        firstSourceLine: Int = 2,
        locale: Locale? = nil
    ) -> [InventoryImportRow] {
        CSVInventoryRowBuilder.rows(
            from: rows,
            mapping: mapping,
            firstSourceLine: firstSourceLine,
            locale: locale ?? american,
            calendar: calendar
        )
    }

    @Test func rows_QuantityWithUnit_FillsUnitWhenColumnUnmapped() throws {
        let rows = build([["Olive oil", "500 g"]], [0: .name, 1: .quantity])
        let row = try #require(rows.first)

        #expect(row.name == "Olive oil")
        #expect(row.quantity == 500)
        #expect(row.unit == .grams)
        #expect(row.issues.isEmpty)
    }

    @Test func rows_QuantityWithoutUnit_TakesUnitColumn() throws {
        let rows = build([["Lye", "2", "kg"]], [0: .name, 1: .quantity, 2: .unit])
        let row = try #require(rows.first)

        #expect(row.quantity == 2)
        #expect(row.unit == .kilograms)
    }

    @Test func rows_QuantityUnitFilledWhenUnitColumnEmpty() throws {
        let rows = build([["Lye", "2 kg", ""]], [0: .name, 1: .quantity, 2: .unit])
        let row = try #require(rows.first)

        #expect(row.unit == .kilograms)
        #expect(row.issues.isEmpty)
    }

    @Test func rows_SameUnitInBoth_IsFine() throws {
        let rows = build([["Lye", "2 kg", "Kilograms"]], [0: .name, 1: .quantity, 2: .unit])
        let row = try #require(rows.first)

        #expect(row.unit == .kilograms)
        #expect(row.issues.isEmpty)
    }

    @Test func rows_ConflictingUnits_Blocks() throws {
        let rows = build([["Lye", "2 kg", "g"]], [0: .name, 1: .quantity, 2: .unit])
        let row = try #require(rows.first)

        #expect(row.issues == [.conflictingUnits(quantityUnit: "kg", unitColumn: "g")])
        #expect(row.issues.map(\.severity) == [.blocking])
    }

    @Test func rows_UnknownUnitColumn_Blocks() throws {
        let rows = build([["Lye", "2", "bucket"]], [0: .name, 1: .quantity, 2: .unit])
        let row = try #require(rows.first)

        #expect(row.issues == [.unknownUnit("bucket")])
        #expect(row.unit == nil)
    }

    @Test func rows_UnknownUnitInQuantityCell_ReportsUnknownUnit() throws {
        let rows = build([["Lye", "2 buckets"]], [0: .name, 1: .quantity])
        let row = try #require(rows.first)

        #expect(row.issues == [.unknownUnit("buckets")])
        #expect(row.quantity == nil)
    }

    @Test func rows_UnreadableQuantity_ReportsInvalidQuantity() throws {
        let rows = build([["Lye", "lots"]], [0: .name, 1: .quantity])
        let row = try #require(rows.first)

        #expect(row.issues == [.invalidQuantity])
        #expect(row.quantity == nil)
    }

    @Test func rows_NegativeQuantity_ReportsInvalidQuantity() throws {
        let rows = build([["Lye", "-5"]], [0: .name, 1: .quantity])
        let row = try #require(rows.first)

        #expect(row.issues == [.invalidQuantity])
    }

    @Test func rows_EmptyQuantityAndUnit_AreNotIssues() throws {
        let rows = build([["Lye", "", ""]], [0: .name, 1: .quantity, 2: .unit])
        let row = try #require(rows.first)

        #expect(row.issues.isEmpty)
        #expect(row.quantity == nil)
        #expect(row.unit == nil)
    }

    @Test func rows_UnitPriceTimesQuantity_FillsTotal() throws {
        let rows = build([["Lye", "500 g", "0.02"]], [0: .name, 1: .quantity, 2: .unitPrice])
        let row = try #require(rows.first)

        #expect(row.totalPrice == 10)
    }

    @Test func rows_UnitPriceWithoutQuantity_LeavesTotalNil() throws {
        let rows = build([["Lye", "", "0.02"]], [0: .name, 1: .quantity, 2: .unitPrice])
        let row = try #require(rows.first)

        #expect(row.totalPrice == nil)
        #expect(row.issues.isEmpty)
    }

    @Test func rows_TotalAndUnitPrice_TotalWins() throws {
        let rows = build([["Lye", "500", "12", "0.5"]], [0: .name, 1: .quantity, 2: .totalPrice, 3: .unitPrice])
        let row = try #require(rows.first)

        #expect(row.totalPrice == 12)
    }

    @Test func rows_UnreadableTotal_FallsBackToUnitPriceAndWarns() throws {
        let rows = build([["Lye", "10", "free", "2"]], [0: .name, 1: .quantity, 2: .totalPrice, 3: .unitPrice])
        let row = try #require(rows.first)

        #expect(row.totalPrice == 20)
        #expect(row.issues == [.unreadablePrice("free")])
        #expect(row.issues.map(\.severity) == [.warning])
    }

    @Test func rows_UnreadablePrice_WarnsAndLeavesNil() throws {
        let rows = build([["Lye", "n/a"]], [0: .name, 1: .totalPrice])
        let row = try #require(rows.first)

        #expect(row.totalPrice == nil)
        #expect(row.issues == [.unreadablePrice("n/a")])
    }

    @Test func rows_CommaDecimalColumn_ReadsDecimals() throws {
        let rows = build([["A", "1,5"], ["B", "2,25"]], [0: .name, 1: .quantity], locale: portuguese)

        #expect(rows.map(\.quantity) == [1.5, 2.25])
    }

    @Test func rows_CommaDecimalColumnUnderEnglishLocale_ReadsDecimals() throws {
        let rows = build([["A", "1,5"], ["B", "2,25"]], [0: .name, 1: .totalPrice])

        #expect(rows.map(\.totalPrice) == [1.5, 2.25])
    }

    @Test func rows_Dates_AreParsed() throws {
        let rows = build(
            [["Lye", "2026-03-15", "2027-01-31"]],
            [0: .name, 1: .purchaseDate, 2: .expiryDate]
        )
        let row = try #require(rows.first)

        #expect(row.purchaseDate == calendar.date(from: DateComponents(year: 2026, month: 3, day: 15)))
        #expect(row.expiryDate == calendar.date(from: DateComponents(year: 2027, month: 1, day: 31)))
        #expect(row.issues.isEmpty)
    }

    @Test func rows_UnreadableDate_WarnsAndLeavesNil() throws {
        let rows = build([["Lye", "someday", "soon"]], [0: .name, 1: .purchaseDate, 2: .expiryDate])
        let row = try #require(rows.first)

        #expect(row.purchaseDate == nil)
        #expect(row.expiryDate == nil)
        #expect(row.issues == [.unreadableDate("someday"), .unreadableDate("soon")])
    }

    @Test func rows_TextFields_AreTrimmedAndEmptyBecomesNil() throws {
        let rows = build(
            [["  Lye ", " Soap Co ", "  "], ["Oil", "", "Oils"]],
            [0: .name, 1: .supplier, 2: .category]
        )

        #expect(rows[0].name == "Lye")
        #expect(rows[0].supplier == "Soap Co")
        #expect(rows[0].categoryName == nil)
        #expect(rows[1].supplier == nil)
        #expect(rows[1].categoryName == "Oils")
    }

    @Test func rows_EmptyName_StaysEmptyForTheMatcher() throws {
        let rows = build([["", "5"]], [0: .name, 1: .quantity])
        let row = try #require(rows.first)

        #expect(row.name == "")
        #expect(row.issues.isEmpty)
    }

    @Test func rows_BlankRows_AreDroppedButKeepTheirLineNumbers() {
        let rows = build([["A", "1"], ["", "  "], [], ["B", "2"]], [0: .name, 1: .quantity])

        #expect(rows.map(\.name) == ["A", "B"])
        #expect(rows.map(\.sourceLine) == [2, 5])
    }

    @Test func rows_ShortRows_ReadMissingCellsAsEmpty() throws {
        let rows = build([["Lye"], ["Oil", "5 g", "9", "extra"]], [0: .name, 1: .quantity, 2: .totalPrice, 5: .supplier])

        #expect(rows.count == 2)
        #expect(rows[0].quantity == nil)
        #expect(rows[0].issues.isEmpty)
        #expect(rows[1].quantity == 5)
        #expect(rows[1].totalPrice == 9)
        #expect(rows[1].supplier == nil)
    }

    @Test func rows_SourceLine_CountsFromFirstSourceLine() {
        let withHeader = build([["A"], ["B"]], [0: .name], firstSourceLine: 2)
        let withoutHeader = build([["A"], ["B"]], [0: .name], firstSourceLine: 1)

        #expect(withHeader.map(\.sourceLine) == [2, 3])
        #expect(withoutHeader.map(\.sourceLine) == [1, 2])
    }

    @Test func rows_NoRows_ReturnsEmpty() {
        #expect(build([], [0: .name]).isEmpty)
    }

    @Test func rows_UnmappedFields_AreIgnored() throws {
        let rows = build([["Lye", "500 g", "ignored"]], [0: .name])
        let row = try #require(rows.first)

        #expect(row.quantity == nil)
        #expect(row.unit == nil)
    }
}
