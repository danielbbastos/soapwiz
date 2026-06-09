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

/// Converts ingredient amounts across both mass and volume units. Mass↔mass
/// crossings delegate to `MassUnitConverter`; volume↔mass crossings use the
/// ingredient's density (g/mL), falling back to a shared default when none is
/// recorded. This is the single conversion path that callers needing
/// volume↔mass — recipe stock deduction, cost — should reuse.
///
/// The reference is `g/mL = kg/L` (numerically identical, so one coefficient
/// covers mL→g and L→kg) quoted @20 °C. There is no temperature input: oil
/// density drifts only ~0.0007 g/mL per °C, well under 1.5% across any realistic
/// swing.
enum IngredientUnitConverter {
    /// Average soaping-oil density used when a volumetric ingredient records no
    /// density of its own. @20 °C reference.
    static let defaultDensity: Double = 0.92

    /// Outcome of a conversion: the converted `value`, the `density` applied to a
    /// volume↔mass crossing (`nil` when no density was needed), and whether that
    /// density fell back to `defaultDensity` rather than a stored value.
    struct Result: Equatable {
        let value: Double
        let density: Double?
        let usedDefaultDensity: Bool
    }

    /// Whether the symbol names a volume unit this converter understands.
    static func isVolume(_ symbol: String) -> Bool {
        symbol == "ml" || symbol == "L"
    }

    /// Amount expressed in millilitres for a known volume unit, or `nil` otherwise.
    private static func milliliters(_ amount: Double, from symbol: String) -> Double? {
        switch symbol {
        case "ml": amount
        case "L": amount * 1000
        default: nil
        }
    }

    /// Converts an amount in millilitres into a known volume unit, or `nil` otherwise.
    private static func fromMilliliters(_ ml: Double, to symbol: String) -> Double? {
        switch symbol {
        case "ml": ml
        case "L": ml / 1000
        default: nil
        }
    }

    /// Converts `amount` from one unit to another, applying `density` (g/mL) for
    /// any volume↔mass crossing and falling back to `defaultDensity` when it's
    /// `nil`. Returns `nil` when either unit is unknown or non-convertible
    /// (e.g. "un" or a percentage).
    static func convert(_ amount: Double, from: String, to: String, density: Double?) -> Result? {
        // Mass ↔ mass: no density involved.
        if let mass = MassUnitConverter.convert(amount, from: from, to: to) {
            return Result(value: mass, density: nil, usedDefaultDensity: false)
        }

        let fromVolume = isVolume(from)
        let toVolume = isVolume(to)

        // Volume ↔ volume: no density involved.
        if fromVolume, toVolume,
           let ml = milliliters(amount, from: from), let out = fromMilliliters(ml, to: to) {
            return Result(value: out, density: nil, usedDefaultDensity: false)
        }

        // A non-positive density can't describe a real ingredient and would make a
        // volume↔mass crossing divide by zero (or yield zero mass); reject it
        // rather than returning an infinite or meaningless value.
        if let density, density <= 0 { return nil }

        let usedDefault = density == nil
        let d = density ?? defaultDensity

        // Volume → mass: mL × density = grams, then convert grams to the target mass unit.
        if fromVolume, MassUnitConverter.isMass(to), let ml = milliliters(amount, from: from) {
            guard let value = MassUnitConverter.convert(ml * d, from: "g", to: to) else { return nil }
            return Result(value: value, density: d, usedDefaultDensity: usedDefault)
        }

        // Mass → volume: mass → grams, ÷ density = mL, then convert to the target volume unit.
        if MassUnitConverter.isMass(from), toVolume {
            guard let grams = MassUnitConverter.convert(amount, from: from, to: "g"),
                  let out = fromMilliliters(grams / d, to: to) else { return nil }
            return Result(value: out, density: d, usedDefaultDensity: usedDefault)
        }

        return nil
    }
}
