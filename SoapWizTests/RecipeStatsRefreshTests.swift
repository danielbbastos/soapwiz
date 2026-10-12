import Testing
@testable import SoapWiz

@Suite
struct RecipeStatsRefreshTests {

    private func draft(_ name: String, amount: Double = 50) -> OilIngredientDraft {
        OilIngredientDraft(ingredient: Ingredient.mockOil(name: name, naohSap: 0.134), amount: amount)
    }

    @Test func updatesImmediately_NothingShown_ReturnsTrue() {
        #expect(RecipeStatsRefresh.updatesImmediately(from: nil, to: [draft("Olive")]))
    }

    @Test func updatesImmediately_NothingShownAndNoRows_ReturnsTrue() {
        #expect(RecipeStatsRefresh.updatesImmediately(from: nil, to: []))
    }

    @Test func updatesImmediately_IdenticalRows_ReturnsFalse() {
        let rows = [draft("Olive"), draft("Coconut")]
        #expect(!RecipeStatsRefresh.updatesImmediately(from: rows, to: rows))
    }

    @Test func updatesImmediately_OnlyAmountChanged_ReturnsFalse() {
        let shown = [draft("Olive"), draft("Coconut")]
        var live = shown
        live[0].amount = 3
        #expect(!RecipeStatsRefresh.updatesImmediately(from: shown, to: live))
    }

    @Test func updatesImmediately_OnlyLockChanged_ReturnsFalse() {
        let shown = [draft("Olive"), draft("Coconut")]
        var live = shown
        live[1].isLocked = true
        #expect(!RecipeStatsRefresh.updatesImmediately(from: shown, to: live))
    }

    @Test func updatesImmediately_RowAdded_ReturnsTrue() {
        let shown = [draft("Olive")]
        let live = shown + [draft("Coconut")]
        #expect(RecipeStatsRefresh.updatesImmediately(from: shown, to: live))
    }

    @Test func updatesImmediately_RowRemoved_ReturnsTrue() {
        let shown = [draft("Olive"), draft("Coconut")]
        let live = [shown[0]]
        #expect(RecipeStatsRefresh.updatesImmediately(from: shown, to: live))
    }

    @Test func updatesImmediately_RowReplaced_ReturnsTrue() {
        let shown = [draft("Olive"), draft("Coconut")]
        let live = [shown[0], draft("Coconut")]
        #expect(RecipeStatsRefresh.updatesImmediately(from: shown, to: live))
    }

    @Test func updatesImmediately_BothEmpty_ReturnsFalse() {
        #expect(!RecipeStatsRefresh.updatesImmediately(from: [], to: []))
    }
}
