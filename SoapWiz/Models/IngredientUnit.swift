enum IngredientUnit: String, CaseIterable, Codable, Hashable {
    case grams = "g"
    case kilograms = "kg"
    case ounces = "oz"
    case pounds = "lb"
    case milliliters = "ml"
    case liters = "L"
    case units = "un"

    var label: String {
        switch self {
        case .grams: "Grams"
        case .kilograms: "Kilograms"
        case .ounces: "Ounces"
        case .pounds: "Pounds"
        case .milliliters: "Millilitres"
        case .liters: "Litres"
        case .units: "Units"
        }
    }
}
