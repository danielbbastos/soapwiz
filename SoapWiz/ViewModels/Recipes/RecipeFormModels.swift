import SwiftUI
import SwiftData

// MARK: - Draft row types

struct OilIngredientDraft: Identifiable, Equatable {
    let id = UUID()
    let ingredient: Ingredient
    var amount: Double = 0
    var isLocked: Bool = false
}

struct IngredientAmountDraft: Identifiable, Equatable {
    let id = UUID()
    let ingredient: Ingredient
    var amount: Double = 0
    var unit: String
    var isLocked: Bool = false
}

struct RecipeProductDraft: Identifiable, Equatable {
    let id = UUID()
    var size: Double = 0
    var unitSymbol: String = ""
    var modelID: PersistentIdentifier?

    /// The unsaved row the form seeds itself with when a recipe has no products
    /// of its own. It stands for the whole batch, which already has its own
    /// figures wherever products are listed, so it is never written to the
    /// store — persisting it would leave behind a product the user never asked
    /// for and no screen shows. A row that once was saved has a `modelID` and
    /// is a real product, whatever its size.
    var isSeededPlaceholder: Bool {
        modelID == nil && unitSymbol == ProductUnit.partsOfBatch.rawValue && size <= 1
    }
}

/// Every user-editable field of the recipe form, captured so the form can tell
/// whether leaving it would lose work. Compared as a whole rather than field by
/// field so a new form field can't silently escape the check.
struct RecipeFormSnapshot: Equatable {
    var name: String
    var desc: String
    var weightUnit: String
    var totalOilWeight: Double
    var oilWeightUnit: String
    var lyeType: String
    var lyePurity: Double
    var waterParts: Double
    var superFat: Double
    var oilDrafts: [OilIngredientDraft]
    var additiveDrafts: [IngredientAmountDraft]
    var fragranceDrafts: [IngredientAmountDraft]
    var productDrafts: [RecipeProductDraft]
    var fragrancePercentage: Double
    var useHybrid: Bool
    var kohPercentage: Double
    var naohPercentage: Double
    var kohPurity: Double
    var naohPurity: Double
    var isCreamSoap: Bool
    var useCFM: Bool
    var cfmNeutralizer: CFMNeutralizer
    var lyeIngredient: Ingredient?
    var kohLyeIngredient: Ingredient?
}

/// The units the recipe form offers for additive and fragrance rows. Shared so
/// recipe import can check an imported unit against the same list the pickers
/// show, rather than keeping a second copy that can drift.
enum RecipeUnitOptions {
    static let additive = ["g", "kg", "oz", "lb", "ml", "L", "% of batch", "% of liquids", "% of oils"]
    static let fragrance = ["g", "oz", "ml", "% of batch", "% of liquids", "% of oils"]
}

// MARK: - Soap method types

/// The neutraliser used by the Catherine Failor method to mop up the 10% excess
/// lye. Each is dosed as the same total solution mass (¾ oz per lb of soap),
/// differing only in how much of that solution is the solid vs. water.
enum CFMNeutralizer: String, CaseIterable {
    case boricAcid = "boric"
    case borax

    var displayName: String {
        switch self {
        case .boricAcid: "Boric Acid"
        case .borax: "Borax"
        }
    }

    /// Fraction of the neutraliser solution that is the solid (the remainder is
    /// water): boric acid makes a 20% solution, borax a 33% solution.
    var solidFraction: Double {
        switch self {
        case .boricAcid: 0.20
        case .borax: 0.33
        }
    }

    /// Resolves a stored raw value to a case, defaulting to boric acid.
    static func resolve(_ raw: String) -> CFMNeutralizer {
        CFMNeutralizer(rawValue: raw) ?? .boricAcid
    }
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
