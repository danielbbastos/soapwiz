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
    var size: Double = 0 {
        didSet { if size != oldValue { isSeededPlaceholder = false } }
    }
    var unitSymbol: String = "" {
        didSet { if unitSymbol != oldValue { isSeededPlaceholder = false } }
    }
    var modelID: PersistentIdentifier?

    /// Marks the unsaved row the form seeds itself with when a recipe has no
    /// products of its own. It stands for the whole batch, which already has its
    /// own figures wherever products are listed, so it is never written to the
    /// store — persisting it would leave behind a product the user never asked
    /// for and no screen shows. Touching either field hands the row to the user
    /// and clears the mark, so an edited seed is saved like any other product.
    ///
    /// Stamped rather than inferred from the row's shape: a product the user
    /// added can end up looking exactly like the seed — picking "parts of batch"
    /// for a fresh row snaps its size to 1 — and that row must still be saved.
    private(set) var isSeededPlaceholder = false

    static func seededPlaceholder() -> RecipeProductDraft {
        var draft = RecipeProductDraft(size: 1, unitSymbol: ProductUnit.partsOfBatch.rawValue)
        draft.isSeededPlaceholder = true
        return draft
    }
}

/// Every user-editable field of the recipe form, captured so the form can tell
/// whether leaving it would lose work. Compared as a whole rather than field by
/// field so a new form field can't silently escape the check.
struct RecipeFormSnapshot: Equatable {
    var name: String
    var desc: String
    var imageData: Data?
    var weightUnit: String
    var recipeKind: RecipeKind
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
    var fragranceUnit: FragranceUnit
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
    var selectedCollections: [RecipeCollection]
}

/// The units the recipe form offers for additive rows. Shared so recipe import
/// can check an imported unit against the same list the picker shows, rather
/// than keeping a second copy that can drift. Additives stay stringly-typed;
/// fragrances have the typed `FragranceUnit`.
enum RecipeUnitOptions {
    /// Countable inventory unit. A row in it is a component — a wick, a jar, a
    /// label — rather than part of the mixture: it carries cost and consumes
    /// stock, but contributes no weight, because a count has no mass to convert.
    static let count = "un"

    /// Share of the recipe's declared total weight. The one percentage scale a
    /// non-soap recipe uses, so its base ingredients and its additives add up to
    /// 100% together rather than the additives sitting on top of a base that is
    /// already 100%.
    static let percentOfTotal = "% of total"

    static let additive = ["g", "kg", "oz", "lb", "ml", "L", "% of batch", "% of liquids", "% of oils", count]

    /// The single string test for "is this a percentage-based unit". Both
    /// additive and fragrance rows reach it as raw strings, through the
    /// `IngredientAmountDraft` the detail view renders.
    static func isPercentage(_ unit: String) -> Bool {
        unit.hasPrefix("%")
    }

    static func isCount(_ unit: String) -> Bool { unit == count }
}

/// The recipe-wide unit every fragrance row is entered in, stored on `Recipe`
/// as its raw value. `percentOfFragrances` means share of the fragrance blend:
/// rows sum to 100% and the absolute load comes from the recipe-level
/// `fragrancePercentage` (% of oils), so changing the load scales the weights
/// while the blend ratios hold.
enum FragranceUnit: String, CaseIterable {
    case grams = "g"
    case ounces = "oz"
    case milliliters = "ml"
    case percentOfBatch = "% of batch"
    case percentOfLiquids = "% of liquids"
    case percentOfOils = "% of oils"
    case percentOfFragrances = "% of fragrances"

    /// Resolves a stored raw value to a case, defaulting to percent of oils.
    static func resolve(_ raw: String) -> FragranceUnit {
        FragranceUnit(rawValue: raw) ?? .percentOfOils
    }
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

    /// The amount in the batch (oils) unit — or, for a count row, the count
    /// itself. `isCountBased` is what tells the two apart.
    let ingredientAmount: Double
    let cost: Double

    /// Whether `ingredientAmount` is a count rather than a weight. Count rows
    /// are priced and deducted like any other, but are left out of every weight
    /// total: adding "1" to a gram figure would be meaningless.
    var isCountBased: Bool = false
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
