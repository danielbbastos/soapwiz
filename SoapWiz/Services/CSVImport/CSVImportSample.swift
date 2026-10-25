import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A small spreadsheet the import screen offers as a starting point: headers
/// the import recognises, and a row for each way a quantity and a price can be
/// written. Dates are ISO and decimals use a dot, which read the same in every
/// region.
struct CSVImportSample: Transferable {
    static let text = """
        Name,Category,Quantity,Unit,Total price,Price per unit,Supplier,Purchase date,Expiry date
        Olive Oil,Oils,1000,g,8.50,,Acme Oils,2026-01-15,2027-06-30
        Shea Butter,Butters,500,g,12.00,,Acme Oils,2026-02-03,
        Rose Clay,Additives,250 g,,4.75,,Clay Corner,2026-02-20,
        Sweet Almond Oil,Oils,2,kg,,9.20,Acme Oils,2026-03-10,2027-09-01

        """

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { _ in
            Data(text.utf8)
        }
        .suggestedFileName("SoapWiz Inventory Sample.csv")
    }
}
