import Foundation

/// Mold shape the calculator supports. Rectangular covers loaf and slab molds;
/// cylindrical covers tube/pipe molds.
enum MoldShape: String, CaseIterable, Identifiable {
    case rectangular
    case cylindrical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rectangular: "Rectangular"
        case .cylindrical: "Cylindrical"
        }
    }
}

/// How full the mold is poured. The factor already bakes in a standard amount of
/// headroom; `extraHeadroom` uses a smaller factor to leave 5–10% more room for
/// fragrance/additives that expand the batter.
enum MoldFillMode: String, CaseIterable, Identifiable {
    case standard
    case extraHeadroom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .extraHeadroom: "Extra headroom"
        }
    }
}

/// Length unit the dimensions are entered in. Each maps to the mass unit its
/// empirical fill factor is calibrated for: cm³→g, in³→oz.
enum MoldLengthUnit: String, CaseIterable, Identifiable {
    case centimeters = "cm"
    case inches = "in"

    var id: String { rawValue }

    /// The mass unit the raw oil-weight factor produces for this length unit.
    var massUnit: String {
        switch self {
        case .centimeters: "g"
        case .inches: "oz"
        }
    }
}

/// Dimensions for a mold, in the chosen `MoldLengthUnit`. Only the fields
/// relevant to the selected shape are used.
struct MoldDimensions: Equatable {
    var length: Double = 0
    var width: Double = 0
    var diameter: Double = 0
    var depth: Double = 0
}

/// Converts mold dimensions into a recommended total oil weight.
///
/// The oil-weight factors are empirical fill factors (not real densities): they
/// already account for the headroom soap batter needs above the oils + lye +
/// water + additives it becomes. Standard leaves the usual headroom; extra
/// headroom uses a smaller factor for ~5–10% more room.
enum MoldCalculator {
    /// Standard fill factor (g per cm³ / oz per in³).
    static func standardFactor(for unit: MoldLengthUnit) -> Double {
        switch unit {
        case .centimeters: 0.70
        case .inches: 0.40
        }
    }

    /// Extra-headroom fill factor — the midpoint of LyeCalc's published ranges
    /// (0.63–0.67 g/cm³, 0.36–0.38 oz/in³).
    static func extraHeadroomFactor(for unit: MoldLengthUnit) -> Double {
        switch unit {
        case .centimeters: 0.65
        case .inches: 0.37
        }
    }

    static func factor(for unit: MoldLengthUnit, fillMode: MoldFillMode) -> Double {
        switch fillMode {
        case .standard: standardFactor(for: unit)
        case .extraHeadroom: extraHeadroomFactor(for: unit)
        }
    }

    /// Mold volume in cubic length-units (cm³ or in³). Rectangular = L×W×D;
    /// cylindrical = π·D²·depth/4.
    static func volume(shape: MoldShape, dimensions: MoldDimensions) -> Double {
        switch shape {
        case .rectangular:
            return dimensions.length * dimensions.width * dimensions.depth
        case .cylindrical:
            return .pi * dimensions.diameter * dimensions.diameter * dimensions.depth / 4
        }
    }

    /// Recommended oil weight in `lengthUnit`'s natural mass unit (g for cm,
    /// oz for in).
    static func oilWeight(
        shape: MoldShape,
        dimensions: MoldDimensions,
        lengthUnit: MoldLengthUnit,
        fillMode: MoldFillMode
    ) -> Double {
        volume(shape: shape, dimensions: dimensions) * factor(for: lengthUnit, fillMode: fillMode)
    }

    /// Recommended oil weight converted into `targetUnit` (a mass unit such as
    /// g / oz / lb / kg). Returns `nil` when `targetUnit` isn't a mass unit.
    static func oilWeight(
        shape: MoldShape,
        dimensions: MoldDimensions,
        lengthUnit: MoldLengthUnit,
        fillMode: MoldFillMode,
        in targetUnit: String
    ) -> Double? {
        let natural = oilWeight(shape: shape, dimensions: dimensions, lengthUnit: lengthUnit, fillMode: fillMode)
        return MassUnitConverter.convert(natural, from: lengthUnit.massUnit, to: targetUnit)
    }
}
