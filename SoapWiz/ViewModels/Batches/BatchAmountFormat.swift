import Foundation

/// How Create Batch and Home write an ingredient amount, so a shortfall reads
/// the same in both.
enum BatchAmountFormat {
    static func number(_ amount: Double) -> String {
        amount.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func amount(_ amount: Double, unit: String) -> String {
        "\(number(amount)) \(unit)"
    }
}
