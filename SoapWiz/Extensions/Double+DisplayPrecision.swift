import Foundation

extension Double {
    /// Whether the two values are equal once both are rounded to
    /// `fractionDigits` decimal places, which is how a field showing that many
    /// digits would tell them apart. Also absorbs floating-point noise.
    func matches(_ other: Double, fractionDigits: Int) -> Bool {
        let scale = pow(10, Double(fractionDigits))
        return (self * scale).rounded() == (other * scale).rounded()
    }
}
