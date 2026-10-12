import Testing
import CoreGraphics
@testable import SoapWiz

@Suite
struct RecipeFormLayoutTests {

    @Test func tabs_Wide_MergesIngredientsAndStats() {
        #expect(RecipeTab.tabs(isWide: true) == [.config, .ingredientsAndStats])
    }

    @Test func tabs_Narrow_ListsThreeTabs() {
        #expect(RecipeTab.tabs(isWide: false) == [.config, .ingredients, .stats])
    }

    @Test(arguments: [
        (RecipeTab.config, true, RecipeTab.config),
        (RecipeTab.ingredients, true, RecipeTab.ingredientsAndStats),
        (RecipeTab.stats, true, RecipeTab.ingredientsAndStats),
        (RecipeTab.ingredientsAndStats, true, RecipeTab.ingredientsAndStats),
        (RecipeTab.config, false, RecipeTab.config),
        (RecipeTab.ingredients, false, RecipeTab.ingredients),
        (RecipeTab.stats, false, RecipeTab.stats),
        (RecipeTab.ingredientsAndStats, false, RecipeTab.ingredients)
    ])
    func adapted_TabAndLayout_ReturnsExpectedTab(tab: RecipeTab, isWide: Bool, expected: RecipeTab) {
        #expect(tab.adapted(isWide: isWide) == expected)
    }

    @Test(arguments: [
        (CGFloat(820), false),
        (CGFloat(999), false),
        (CGFloat(1_000), true),
        (CGFloat(1_180), true)
    ])
    func isWide_Width_MatchesThreshold(width: CGFloat, expected: Bool) {
        #expect(RecipeFormLayout.isWide(width: width) == expected)
    }
}
