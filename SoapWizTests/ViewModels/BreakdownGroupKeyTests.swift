import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("BreakdownGroupKey – group order")
@MainActor
struct BreakdownGroupKeyTests {

    private func row(isNeutralizer: Bool = false) -> IngredientProductBreakdown {
        IngredientProductBreakdown(
            ingredient: Ingredient(name: "Ingredient"), ingredientAmount: 100, cost: 1,
            isNeutralizer: isNeutralizer
        )
    }

    @Test func groups_AllGroupsFilled_AreInDisplayOrder() throws {
        let container = try ModelContainer(
            for: Ingredient.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        _ = container
        let breakdown = ProductCostBreakdown(
            oils: [row()],
            additives: [row(), row(isNeutralizer: true)],
            fragrances: [row()],
            lye: [row()]
        )

        let keys = BreakdownGroupKey.groups(of: breakdown).map(\.key)

        #expect(keys == [.oils, .lye, .additives, .neutralizer, .fragrances])
    }

    @Test func groups_EmptyGroups_AreLeftOut() throws {
        let container = try ModelContainer(
            for: Ingredient.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        _ = container
        let breakdown = ProductCostBreakdown(oils: [row()], fragrances: [row()], lye: [row()])

        let keys = BreakdownGroupKey.groups(of: breakdown).map(\.key)

        #expect(keys == [.oils, .lye, .fragrances])
    }

    @Test func groups_EmptyBreakdown_ReturnsNoGroups() {
        #expect(BreakdownGroupKey.groups(of: ProductCostBreakdown()).isEmpty)
    }
}
