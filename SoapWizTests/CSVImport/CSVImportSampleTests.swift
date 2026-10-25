import Foundation
import Testing
@testable import SoapWiz

@Suite
struct CSVImportSampleTests {
    private let locale = Locale(identifier: "en_US_POSIX")

    private func makeMapping() -> CSVMappingViewModel {
        CSVMappingViewModel(
            rows: CSVReader.rows(from: CSVImportSample.text),
            locale: locale,
            calendar: Calendar(identifier: .gregorian)
        )
    }

    @Test func sample_MapsEveryColumnToADistinctField() {
        let sut = makeMapping()

        let fields = sut.columns.map { sut.field(for: $0.index) }

        #expect(fields.allSatisfy { $0 != nil })
        #expect(Set(fields.compactMap { $0 }) == Set(InventoryImportField.allCases))
        #expect(sut.hasHeaderRow)
        #expect(sut.canContinue)
    }

    @Test func sample_BuildsRowsWithoutIssues() {
        let rows = makeMapping().rowInput.rows()

        #expect(rows.count == 4)
        #expect(rows.allSatisfy { $0.issues.isEmpty })
        #expect(rows.allSatisfy { $0.quantity != nil && $0.unit != nil })
    }

    @Test func sample_QuantityWithUnitAndUnitPriceRows_ReadCorrectly() throws {
        let rows = makeMapping().rowInput.rows()

        let clay = try #require(rows.first { $0.name == "Rose Clay" })
        #expect(clay.quantity == 250)
        #expect(clay.unit == .grams)
        let almond = try #require(rows.first { $0.name == "Sweet Almond Oil" })
        #expect(almond.unit == .kilograms)
        #expect(almond.totalPrice != nil)
    }
}
