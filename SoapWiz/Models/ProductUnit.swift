enum ProductUnit: String, CaseIterable, Codable, Hashable {
    case wholeBatch = "whole batch"
    case grams = "g"
    case kilograms = "kg"
    case ounces = "oz"
    case pounds = "lb"
    case partsOfBatch = "parts of batch"

    var label: String {
        switch self {
        case .wholeBatch: "Whole batch"
        case .grams: "Grams"
        case .kilograms: "Kilograms"
        case .ounces: "Ounces"
        case .pounds: "Pounds"
        case .partsOfBatch: "Parts of total batch"
        }
    }

    var isMassUnit: Bool {
        switch self {
        case .grams, .kilograms, .ounces, .pounds: true
        case .wholeBatch, .partsOfBatch: false
        }
    }

    var requiresSize: Bool {
        switch self {
        case .wholeBatch: false
        default: true
        }
    }

    /// Whether a size in this unit costs something other than the whole batch.
    /// A whole batch, or a batch split into one part, is the batch total again,
    /// which every cost screen already shows. Parts of a batch are a whole
    /// number of them, two or more; anything else is not a size. An unknown
    /// unit symbol is treated like a mass unit, as it always has been.
    static func isSeparateFromBatch(size: Double, unitSymbol: String) -> Bool {
        switch ProductUnit(rawValue: unitSymbol) {
        case .wholeBatch: false
        case .partsOfBatch: size > 1 && size == size.rounded()
        case .grams, .kilograms, .ounces, .pounds, nil: true
        }
    }

    var gramsPerUnit: Double? {
        switch self {
        case .grams: 1
        case .kilograms: 1000
        case .ounces: 28.3495
        case .pounds: 453.592
        case .wholeBatch, .partsOfBatch: nil
        }
    }
}
