/// The four groups a `ProductCostBreakdown` is presented in. Shared by the
/// form's product card and the detail screen's cost section, which render the
/// same grouping very differently but must agree on its order and labels.
enum BreakdownGroupKey: String, CaseIterable {
    case oils, additives, fragrances, lye

    var displayName: String {
        switch self {
        case .oils: "Oils"
        case .additives: "Additives"
        case .fragrances: "Fragrances"
        case .lye: "Lye"
        }
    }

    /// Only additives and fragrances carry a user-chosen unit; oils and lye are
    /// always shown in the oil weight unit.
    var usesEnteredUnit: Bool {
        self == .additives || self == .fragrances
    }

    private func rows(of breakdown: ProductCostBreakdown) -> [IngredientProductBreakdown] {
        switch self {
        case .oils: breakdown.oils
        case .additives: breakdown.additives
        case .fragrances: breakdown.fragrances
        case .lye: breakdown.lye
        }
    }

    /// The breakdown's non-empty groups, in display order.
    static func groups(of breakdown: ProductCostBreakdown) -> [(key: BreakdownGroupKey, rows: [IngredientProductBreakdown])] {
        allCases.compactMap { key in
            let rows = key.rows(of: breakdown)
            return rows.isEmpty ? nil : (key, rows)
        }
    }
}
