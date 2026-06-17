import SwiftUI
import SwiftData

// MARK: - Draft row types

struct OilIngredientDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var amount: Double = 0
    var isLocked: Bool = false
}

struct IngredientAmountDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var amount: Double = 0
    var unit: String
    var isLocked: Bool = false
}

struct RecipeProductDraft: Identifiable {
    let id = UUID()
    var size: Double = 0
    var unitSymbol: String = ""
    var modelID: PersistentIdentifier?
}

// MARK: - Calculated value types

struct FragranceTarget {
    /// e.g. "45 g (3%)"
    let text: String
    /// The configured fragrance percentage, for the explanatory tooltip.
    let percentage: Double
    /// Whether the entered fragrance total exceeds the recommended target.
    let isOverTarget: Bool
}

struct IngredientProductBreakdown {
    let ingredient: Ingredient
    let ingredientAmount: Double
    let cost: Double
}

struct BreakdownAmountDisplay {
    let amount: Double
    let unit: String
    /// Explanation of the volume↔mass crossing behind the amount, shown in an
    /// info popover, e.g. "100 ml ≈ 126 g, converted using the ingredient's
    /// density of 1.26 g/ml.". `nil` when no density was used.
    let conversionNote: String?
}

struct ProductCostBreakdown {
    var oils: [IngredientProductBreakdown] = []
    var additives: [IngredientProductBreakdown] = []
    var fragrances: [IngredientProductBreakdown] = []
    var lye: [IngredientProductBreakdown] = []
    var total: Double = 0
    var exceedsBatchWeight: Bool = false
}

struct OilAmountCalculation: Identifiable {
    let id: UUID
    let ingredient: Ingredient
    let weight: Double
    /// Lye contributed by this oil, already discounted for super fat. Split so
    /// the hybrid path can price NaOH and KOH separately; the single path puts
    /// everything in `naohLye`.
    let naohLye: Double
    let kohLye: Double
    var lye: Double { naohLye + kohLye }
}

struct CalculatedAmountRow: Identifiable {
    let id = UUID()
    let label: String
    let weight: Double
    let pct: Double
    let isSummary: Bool
}

/// The three suggested-amount columns (1% / 2% / 3% of oils) for an extras row,
/// used for the acid-neutralisation lye sub-rows.
struct LyeTriple {
    let val1: Double
    let val2: Double
    let val3: Double
}

struct ExtraSectionARow: Identifiable {
    let id = UUID()
    let label: String
    let val1: Double
    let val2: Double
    let val3: Double
    let naohLye: LyeTriple?
    let kohLye: LyeTriple?

    init(label: String, val1: Double, val2: Double, val3: Double,
         naohLye: LyeTriple? = nil, kohLye: LyeTriple? = nil) {
        self.label = label
        self.val1 = val1
        self.val2 = val2
        self.val3 = val3
        self.naohLye = naohLye
        self.kohLye = kohLye
    }
}

struct ExtraSectionBRow: Identifiable {
    let id = UUID()
    let label: String
    let minValue: Double
    let maxValue: Double?
    let naohLye: Double?
    let kohLye: Double?

    init(label: String, minValue: Double, maxValue: Double? = nil,
         naohLye: Double? = nil, kohLye: Double? = nil) {
        self.label = label
        self.minValue = minValue
        self.maxValue = maxValue
        self.naohLye = naohLye
        self.kohLye = kohLye
    }
}

/// A lye amount split into its NaOH and KOH portions.
struct LyeSplit {
    let naoh: Double
    let koh: Double
}

/// An amount paired with its unit, used to describe the two sides of a
/// volume↔mass conversion in a breakdown row's info popover.
struct Quantity {
    let amount: Double
    let unit: String
}

// MARK: - Shared helpers

/// Case-insensitive containment in either direction — the single matching rule
/// for extras labels and acid factors, so an ingredient the UI offers as an acid
/// match always gets its lye compensation too.
func ingredientNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
    let lhs = lhs.lowercased(), rhs = rhs.lowercased()
    guard !lhs.isEmpty, !rhs.isEmpty else { return false }
    return lhs.contains(rhs) || rhs.contains(lhs)
}

/// Shared percentage formatter for recipe display labels: rounds to one decimal
/// and formats in the current locale.
enum PercentageFormatter {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func string(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return formatter.string(from: NSNumber(value: rounded)) ?? "0"
    }
}
