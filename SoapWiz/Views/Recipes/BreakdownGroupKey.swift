/// The five groups a `ProductCostBreakdown` is presented in. Shared by the
/// form's product card and the detail screen's cost section, which render the
/// same grouping very differently but must agree on its order and labels.
enum BreakdownGroupKey: String, CaseIterable {
    case oils, additives, neutralizer, fragrances, lye

    var displayName: String {
        switch self {
        case .oils: "Oils"
        case .additives: "Additives"
        case .neutralizer: "Neutralizer"
        case .fragrances: "Fragrances"
        case .lye: "Lye"
        }
    }

    /// Only additives and fragrances carry a user-chosen unit; oils, the
    /// neutraliser and lye are always shown in the oil weight unit.
    var usesEnteredUnit: Bool {
        self == .additives || self == .fragrances
    }

    /// The Failor neutraliser rides in `additives` so every cost, scale and
    /// weight total keeps counting it, but it is pulled into its own group for
    /// display; the additives group excludes it in turn.
    private func rows(of breakdown: ProductCostBreakdown) -> [IngredientProductBreakdown] {
        switch self {
        case .oils: breakdown.oils
        case .additives: breakdown.additives.filter { !$0.isNeutralizer }
        case .neutralizer: breakdown.additives.filter(\.isNeutralizer)
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
