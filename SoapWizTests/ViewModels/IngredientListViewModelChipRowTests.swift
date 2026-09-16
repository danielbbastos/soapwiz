import Testing
import SwiftData
@testable import SoapWiz

@Suite("IngredientListViewModel — category chip row", .serialized)
@MainActor
struct IngredientListViewModelChipRowTests: IngredientFormTestHelpers {

    // MARK: - Chip row selection

    @Test func toggleCategoryAddsThenRemoves() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        ctx.insert(oils)
        try ctx.save()

        let model = IngredientListViewModel()

        model.toggleCategory(oils)
        #expect(model.selectedCategories == [oils.persistentModelID])

        model.toggleCategory(oils)
        #expect(model.selectedCategories.isEmpty)
    }

    @Test func toggleCategoryAccumulatesSelections() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        let lyes = IngredientCategory(name: "Lyes")
        ctx.insert(oils); ctx.insert(lyes)
        try ctx.save()

        let model = IngredientListViewModel()
        model.toggleCategory(oils)
        model.toggleCategory(lyes)

        #expect(model.selectedCategories == [oils.persistentModelID, lyes.persistentModelID])
    }

    @Test func isShowingAllCategoriesTracksTheSelection() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        ctx.insert(oils)
        try ctx.save()

        let model = IngredientListViewModel()
        #expect(model.isShowingAllCategories)

        model.toggleCategory(oils)
        #expect(!model.isShowingAllCategories)
    }

    /// The "All" chip clears categories only. The other three filters live in
    /// the sheet, and a tap on the chip row must not silently reset them.
    @Test func selectAllCategoriesLeavesTheOtherFiltersAlone() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        ctx.insert(oils)
        try ctx.save()

        let model = IngredientListViewModel()
        model.toggleCategory(oils)
        model.stockStatus = .lowStock
        model.expiryFilter = .expired
        model.selectedUnits = [.grams]

        model.selectAllCategories()

        #expect(model.selectedCategories.isEmpty)
        #expect(model.stockStatus == .lowStock)
        #expect(model.expiryFilter == .expired)
        #expect(model.selectedUnits == [.grams])
    }

    // MARK: - visibleCategories

    @Test func visibleCategoriesHidesCategoriesWithNoIngredients() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        let waxes = IngredientCategory(name: "Waxes")
        ctx.insert(oils); ctx.insert(waxes)
        let olive = Ingredient(name: "Olive Oil", category: oils)
        ctx.insert(olive)
        try ctx.save()

        let model = IngredientListViewModel()
        let visible = model.visibleCategories([oils, waxes], in: [olive])

        #expect(visible.map(\.name) == ["Oils"])
    }

    /// A category that empties while it is the active filter has to stay, or the
    /// chip row would reshuffle under the tap that just set it.
    @Test func visibleCategoriesKeepsAnEmptyCategoryWhileItIsSelected() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        let waxes = IngredientCategory(name: "Waxes")
        ctx.insert(oils); ctx.insert(waxes)
        let olive = Ingredient(name: "Olive Oil", category: oils)
        ctx.insert(olive)
        try ctx.save()

        let model = IngredientListViewModel()
        model.toggleCategory(waxes)
        let visible = model.visibleCategories([oils, waxes], in: [olive])

        #expect(visible.map(\.name) == ["Oils", "Waxes"])
    }

    @Test func visibleCategoriesReturnsEveryCategoryInUse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        let lyes = IngredientCategory(name: "Lyes")
        ctx.insert(oils); ctx.insert(lyes)
        let olive = Ingredient(name: "Olive Oil", category: oils)
        let naoh = Ingredient(name: "NaOH", category: lyes)
        ctx.insert(olive); ctx.insert(naoh)
        try ctx.save()

        let model = IngredientListViewModel()
        let visible = model.visibleCategories([oils, lyes], in: [olive, naoh])

        #expect(visible.count == 2)
    }

    /// An empty inventory shows no chips at all rather than seven that all lead
    /// to "No Results".
    @Test func visibleCategoriesIsEmptyWhenNothingIsFiled() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        ctx.insert(oils)
        try ctx.save()

        let model = IngredientListViewModel()

        #expect(model.visibleCategories([oils], in: []).isEmpty)
    }

    @Test func visibleCategoriesIgnoresIngredientsWithNoCategory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        ctx.insert(oils)
        let mystery = Ingredient(name: "Mystery")
        ctx.insert(mystery)
        try ctx.save()

        let model = IngredientListViewModel()

        #expect(model.visibleCategories([oils], in: [mystery]).isEmpty)
    }
}
