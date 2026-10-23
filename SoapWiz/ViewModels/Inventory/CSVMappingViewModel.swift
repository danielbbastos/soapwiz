import Foundation
import Observation

/// One column of the file as the mapping screen lists it.
struct CSVMappingColumn: Identifiable, Equatable {
    let index: Int
    /// The header cell, or "Column n" when the file has no header row or the
    /// cell is blank.
    let title: String
    /// Up to three of the column's first non-empty values below the header.
    let samples: [String]

    var id: Int { index }
}

/// Which spreadsheet column holds which inventory field, before the rows are
/// built.
///
/// Starts from the header row when it names a field, and leaves the mapping
/// empty otherwise. A field belongs to at most one column.
@Observable
final class CSVMappingViewModel {
    private let rows: [[String]]
    private let locale: Locale
    private let calendar: Calendar
    private var mapping: [Int: InventoryImportField]

    /// Whether the first row is a header rather than data. Turning it off
    /// keeps the current mapping, which the user may have set by hand; turning
    /// it on detects the fields from the header only while nothing is mapped.
    var hasHeaderRow: Bool {
        didSet {
            if hasHeaderRow, !oldValue, mapping.isEmpty {
                mapping = InventoryImportField.detect(header: rows.first ?? [])
            }
        }
    }

    init(rows: [[String]], locale: Locale = .autoupdatingCurrent, calendar: Calendar = .current) {
        self.rows = rows
        self.locale = locale
        self.calendar = calendar
        let hasHeader = InventoryImportField.isHeader(rows.first ?? [])
        hasHeaderRow = hasHeader
        mapping = hasHeader ? InventoryImportField.detect(header: rows.first ?? []) : [:]
    }

    private var dataRows: [[String]] {
        hasHeaderRow ? Array(rows.dropFirst()) : rows
    }

    /// The rows below the header that have text in at least one cell.
    private var filledDataRows: [[String]] {
        dataRows.filter { !CSVInventoryRowBuilder.isBlank($0) }
    }

    var columns: [CSVMappingColumn] {
        let count = rows.map(\.count).max() ?? 0
        let header = hasHeaderRow ? rows.first ?? [] : []
        let filled = filledDataRows
        return (0..<count).map { index in
            let headerText = header.indices.contains(index)
                ? header[index].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            let samples = filled
                .compactMap { $0.indices.contains(index) ? $0[index].trimmingCharacters(in: .whitespacesAndNewlines) : nil }
                .filter { !$0.isEmpty }
            return CSVMappingColumn(
                index: index,
                title: headerText.isEmpty ? String(localized: "Column \(index + 1)") : headerText,
                samples: Array(samples.prefix(3))
            )
        }
    }

    var dataRowCount: Int { filledDataRows.count }

    var canContinue: Bool {
        mapping.values.contains(.name) && dataRowCount > 0
    }

    func field(for column: Int) -> InventoryImportField? {
        mapping[column]
    }

    /// Maps `column` to `field`, or clears it with nil. A field already held by
    /// another column moves to this one.
    func setField(_ field: InventoryImportField?, for column: Int) {
        if let field {
            mapping = mapping.filter { $0.value != field }
        }
        mapping[column] = field
    }

    func makeRows() -> [InventoryImportRow] {
        CSVInventoryRowBuilder.rows(
            from: dataRows,
            mapping: mapping,
            firstSourceLine: hasHeaderRow ? 2 : 1,
            locale: locale,
            calendar: calendar
        )
    }
}
