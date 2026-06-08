import Foundation

/// Converts amounts between the mass units used across recipes, backed by
/// Foundation's `Measurement<UnitMass>` so the coefficients are exact.
///
/// Returns `nil` when either symbol isn't a known mass unit (e.g. `ml`, `L`,
/// or a percentage), since those can't be converted to a mass without density.
enum MassUnitConverter {
    private static func unit(for symbol: String) -> UnitMass? {
        switch symbol {
        case "g": .grams
        case "kg": .kilograms
        case "oz": .ounces
        case "lb": .pounds
        default: nil
        }
    }

    /// Whether the symbol names a mass unit this converter understands.
    static func isMass(_ symbol: String) -> Bool { unit(for: symbol) != nil }

    /// Converts `amount` from one mass unit to another. Returns `nil` if either
    /// unit isn't a mass unit.
    static func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let fromUnit = unit(for: from), let toUnit = unit(for: to) else { return nil }
        if fromUnit == toUnit { return amount }
        return Measurement(value: amount, unit: fromUnit).converted(to: toUnit).value
    }
}
