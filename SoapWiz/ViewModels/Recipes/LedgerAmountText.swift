import Foundation

/// An amount as the ledger draws it: the figure in `ink`, then the detail that
/// qualifies it in `inkSoft`, such as its unit and, for a percentage, the
/// weight it comes to.
struct LedgerAmountText: Equatable {
    let figure: String
    let detail: String

    /// `number` is already formatted. A percent sign joins the number, as in
    /// "72%" or "3% of oils"; any other unit follows a space. `convertedWeight`,
    /// already formatted with its unit, follows a middle dot.
    init(number: String, unit: String, convertedWeight: String? = nil) {
        var detail: String
        if unit.hasPrefix("%") {
            figure = number + "%"
            let rest = unit.dropFirst().trimmingCharacters(in: .whitespaces)
            detail = rest.isEmpty ? "" : " " + rest
        } else {
            figure = number
            detail = unit.isEmpty ? "" : " " + unit
        }
        if let convertedWeight {
            detail += " · " + convertedWeight
        }
        self.detail = detail
    }
}

/// The second line of a cost breakdown row.
enum CostBreakdownCaption {
    private static let spelledOut = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

    /// "one of five": how many products of a size one batch makes. Numbers
    /// below ten are spelled out, as in running text.
    static func sizesPerBatch(_ count: Int) -> String {
        let number = (1...9).contains(count) ? spelledOut[count - 1] : "\(count)"
        return "one of \(number)"
    }
}
