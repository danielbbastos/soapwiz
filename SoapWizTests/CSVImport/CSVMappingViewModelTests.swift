import Foundation
import Testing
@testable import SoapWiz

@Suite
struct CSVMappingViewModelTests {
    private let american = Locale(identifier: "en_US")
    private let table = [
        ["Ingredient", "Qty", "Price"],
        ["Olive oil", "500 g", "12.5"],
        ["Lye", "1 kg", "8"]
    ]

    private func makeSUT(_ rows: [[String]]) -> CSVMappingViewModel {
        CSVMappingViewModel(rows: rows, locale: american)
    }

    @Test func init_HeaderRow_DetectsMapping() {
        let sut = makeSUT(table)

        #expect(sut.hasHeaderRow)
        #expect(sut.field(for: 0) == .name)
        #expect(sut.field(for: 1) == .quantity)
        #expect(sut.field(for: 2) == .totalPrice)
    }

    @Test func init_Headerless_HasEmptyMappingAndColumnTitles() {
        let sut = makeSUT([["Olive oil", "500", "12.5"], ["Lye", "1", "8"]])

        #expect(!sut.hasHeaderRow)
        #expect(sut.field(for: 0) == nil)
        #expect(sut.columns.map(\.title) == [
            String(localized: "Column \(1)"), String(localized: "Column \(2)"), String(localized: "Column \(3)")
        ])
        #expect(sut.dataRowCount == 2)
    }

    @Test func columns_HeaderRow_UsesHeaderTitlesAndFirstThreeSamples() throws {
        let sut = makeSUT([["Name", ""], ["A", "1"], ["B", ""], ["C", "3"], ["D", "4"], ["E", "5"]])

        #expect(sut.columns[0].title == "Name")
        #expect(sut.columns[0].samples == ["A", "B", "C"])
        #expect(sut.columns[1].title == String(localized: "Column \(2)"))
        #expect(sut.columns[1].samples == ["1", "3", "4"])
    }

    @Test func columns_RaggedRows_CountsWidestRow() {
        let sut = makeSUT([["Name"], ["A", "1", "x"]])

        #expect(sut.columns.count == 3)
    }

    @Test func hasHeaderRow_TurnedOff_ShiftsSamplesAndCount() {
        let sut = makeSUT(table)

        sut.hasHeaderRow = false

        #expect(sut.dataRowCount == 3)
        #expect(sut.columns[0].samples == ["Ingredient", "Olive oil", "Lye"])
        #expect(sut.columns[0].title == String(localized: "Column \(1)"))
    }

    @Test func hasHeaderRow_TurnedOff_KeepsMapping() {
        let sut = makeSUT(table)

        sut.hasHeaderRow = false

        #expect(sut.field(for: 0) == .name)
    }

    @Test func hasHeaderRow_TurnedOnWithEmptyMapping_Redetects() {
        let sut = makeSUT(table)
        sut.setField(nil, for: 0)
        sut.setField(nil, for: 1)
        sut.setField(nil, for: 2)
        sut.hasHeaderRow = false
        sut.hasHeaderRow = true

        #expect(sut.field(for: 0) == .name)
        #expect(sut.field(for: 2) == .totalPrice)
    }

    @Test func hasHeaderRow_TurnedOnWithMapping_KeepsIt() {
        let sut = makeSUT([["a", "b"], ["c", "d"]])
        sut.setField(.supplier, for: 1)

        sut.hasHeaderRow = true

        #expect(sut.field(for: 1) == .supplier)
        #expect(sut.field(for: 0) == nil)
    }

    @Test func setField_FieldUsedElsewhere_MovesIt() {
        let sut = makeSUT(table)

        sut.setField(.name, for: 2)

        #expect(sut.field(for: 2) == .name)
        #expect(sut.field(for: 0) == nil)
    }

    @Test func setField_Nil_ClearsColumn() {
        let sut = makeSUT(table)

        sut.setField(nil, for: 1)

        #expect(sut.field(for: 1) == nil)
    }

    @Test func canContinue_RequiresNameAndRows() {
        let sut = makeSUT(table)
        #expect(sut.canContinue)

        sut.setField(nil, for: 0)
        #expect(!sut.canContinue)

        let empty = makeSUT([["Name", "Qty"]])
        #expect(empty.dataRowCount == 0)
        #expect(!empty.canContinue)

        let blank = makeSUT([["Name", "Qty"], ["", " "]])
        #expect(!blank.canContinue)
    }

    @Test func makeRows_EndToEnd_WithHeader() throws {
        let sut = makeSUT(table)

        let rows = sut.makeRows()

        #expect(rows.count == 2)
        #expect(rows[0].name == "Olive oil")
        #expect(rows[0].quantity == 500)
        #expect(rows[0].unit == .grams)
        #expect(rows[0].totalPrice == 12.5)
        #expect(rows.map(\.sourceLine) == [2, 3])
        #expect(rows[1].unit == .kilograms)
    }

    @Test func makeRows_Headerless_NumbersFromOne() {
        let sut = makeSUT([["Olive oil", "500 g"], ["Lye", "1 kg"]])
        sut.setField(.name, for: 0)
        sut.setField(.quantity, for: 1)

        let rows = sut.makeRows()

        #expect(rows.map(\.sourceLine) == [1, 2])
        #expect(rows.map(\.name) == ["Olive oil", "Lye"])
    }

    @Test func init_NoRows_IsEmptyAndCannotContinue() {
        let sut = makeSUT([])

        #expect(sut.columns.isEmpty)
        #expect(sut.dataRowCount == 0)
        #expect(!sut.canContinue)
        #expect(sut.makeRows().isEmpty)
    }
}
