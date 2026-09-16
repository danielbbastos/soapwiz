import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Library ingredients are part of the app: they leave Inventory by being hidden,
/// never by being deleted, because the installer would only put a pristine copy
/// back on the next launch.
@Suite("IngredientListViewModel — hiding library ingredients", .serialized)
@MainActor
struct IngredientListViewModelHiddenTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self,
            StorageLocation.self, Provider.self,
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Batch.self, BatchLineItem.self, AppSettings.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    // MARK: - Inventory filtering

    @Test func filtered_HiddenIngredient_IsExcluded() {
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")
        let custom = Ingredient(name: "My Blend")
        olive.isHidden = true

        let model = IngredientListViewModel()

        #expect(model.filtered([olive, custom]).map(\.name) == ["My Blend"])
    }

    @Test func filtered_HiddenIngredientMatchingSearch_IsStillExcluded() {
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")
        olive.isHidden = true

        let model = IngredientListViewModel()
        model.searchText = "olive"

        #expect(model.filtered([olive]).isEmpty)
    }

    @Test func filtered_NothingHidden_ReturnsAll() {
        let model = IngredientListViewModel()
        let all = [Ingredient(name: "A"), Ingredient(name: "B")]

        #expect(model.filtered(all).count == 2)
    }

    /// Hiding takes the row out of Inventory and out of the pickers, but never out of
    /// the store — a recipe already built on it keeps working, and its batches still
    /// deduct from it.
    @Test func hiddenIngredient_RemainsInTheStore() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")
        ctx.insert(olive)
        try ctx.save()

        let model = IngredientListViewModel()
        model.hide(olive)
        try ctx.save()

        #expect(model.filtered([olive]).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).count == 1)
    }

    // MARK: - hidden()

    @Test func hidden_ReturnsOnlyHiddenRows() {
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")
        let coconut = Ingredient.libraryMock(name: "Coconut Oil", slug: "coconut-oil")
        olive.isHidden = true

        let model = IngredientListViewModel()

        #expect(model.hidden([olive, coconut]).map(\.name) == ["Olive Oil"])
    }

    @Test func hidden_NothingHidden_IsEmpty() {
        let model = IngredientListViewModel()

        #expect(model.hidden([Ingredient(name: "A")]).isEmpty)
    }

    // MARK: - hide / unhide

    @Test func hideThenUnhide_RestoresTheRowToInventory() {
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")
        let model = IngredientListViewModel()

        model.hide(olive)
        #expect(olive.isHidden)
        #expect(model.filtered([olive]).isEmpty)

        model.unhide(olive)
        #expect(olive.isHidden == false)
        #expect(model.filtered([olive]).count == 1)
    }

    // MARK: - delete routing

    @Test func delete_LibraryIngredient_HidesImmediatelyWithoutConfirmation() {
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")
        let model = IngredientListViewModel()

        model.delete(olive)

        #expect(olive.isHidden)
        #expect(model.confirmingDelete.isEmpty)
        #expect(model.confirmingHide.isEmpty)
        #expect(model.isConfirmingRemoval == false)
    }

    /// A customised library row is still a library row: deleting it would bring the
    /// pristine entry back, so it hides too.
    @Test func delete_CustomisedLibraryIngredient_StillHides() {
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")
        olive.hasCustomChemistry = true
        #expect(olive.isPristineLibraryRow == false)

        let model = IngredientListViewModel()
        model.delete(olive)

        #expect(olive.isHidden)
    }

    @Test func delete_UserCreatedIngredient_StagesTheConfirmation() {
        let custom = Ingredient(name: "My Blend")
        let model = IngredientListViewModel()

        model.delete(custom)

        #expect(model.confirmingDelete.map(\.name) == ["My Blend"])
        #expect(custom.isHidden == false)
    }

    @Test func delete_UserCreatedIngredientUsedInRecipe_IsBlocked() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let custom = Ingredient(name: "My Blend", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(custom)
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: custom, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(custom)

        #expect(model.deleteBlockedIngredients.map(\.name) == ["My Blend"])
        #expect(model.confirmingDelete.isEmpty)
    }

    /// Recipe usage blocks deletion, not hiding: the row stays exactly where the
    /// recipe expects it.
    @Test func delete_LibraryIngredientUsedInRecipe_HidesAnyway() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(olive)
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)

        #expect(olive.isHidden)
        #expect(model.deleteBlockedIngredients.isEmpty)
    }

    // MARK: - Bulk selection

    @Test func deleteSelected_MixedSelection_StagesHidesAndDeletesSeparately() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")
        let custom = Ingredient(name: "My Blend")
        ctx.insert(olive)
        ctx.insert(custom)
        try ctx.save()

        let model = IngredientListViewModel()
        model.selection = [olive.persistentModelID, custom.persistentModelID]
        model.deleteSelected(in: [olive, custom])

        #expect(model.confirmingHide.map(\.name) == ["Olive Oil"])
        #expect(model.confirmingDelete.map(\.name) == ["My Blend"])
        #expect(model.isConfirmingRemoval)
    }

    /// Nothing is staged at all when a user-created row in the selection is blocked —
    /// a partial removal is harder to reason about than none.
    @Test func deleteSelected_BlockedUserRow_StagesNothingIncludingTheLibraryRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")
        let custom = Ingredient(name: "My Blend", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(olive)
        ctx.insert(custom)
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: custom, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()

        let model = IngredientListViewModel()
        model.selection = [olive.persistentModelID, custom.persistentModelID]
        model.deleteSelected(in: [olive, custom])

        #expect(model.deleteBlockedIngredients.map(\.name) == ["My Blend"])
        #expect(model.confirmingHide.isEmpty)
        #expect(model.confirmingDelete.isEmpty)
    }

    @Test func confirmDelete_MixedSelection_HidesOneAndDeletesTheOther() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")
        let custom = Ingredient(name: "My Blend")
        ctx.insert(olive)
        ctx.insert(custom)
        try ctx.save()

        let model = IngredientListViewModel()
        model.selection = [olive.persistentModelID, custom.persistentModelID]
        model.deleteSelected(in: [olive, custom])
        model.confirmDelete(context: ctx)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(remaining.map(\.name) == ["Olive Oil"])
        #expect(olive.isHidden)
        #expect(model.isConfirmingRemoval == false)
        #expect(model.selection.isEmpty)
    }

    @Test func cancelRemoval_ClearsBothStagedLists() {
        let model = IngredientListViewModel()
        model.confirmingHide = [Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")]
        model.confirmingDelete = [Ingredient(name: "My Blend")]

        model.cancelRemoval()

        #expect(model.isConfirmingRemoval == false)
    }

    // MARK: - Confirmation wording

    @Test func removalConfirmationTitle_OnlyLibraryRows_SaysHide() {
        let model = IngredientListViewModel()
        model.confirmingHide = [Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")]

        #expect(model.removalConfirmationTitle == "Hide Ingredient?")
    }

    @Test func removalConfirmationTitle_OnlyUserRows_SaysDelete() {
        let model = IngredientListViewModel()
        model.confirmingDelete = [Ingredient(name: "My Blend")]

        #expect(model.removalConfirmationTitle == "Delete Ingredient?")
    }

    @Test func removalConfirmationTitle_MixedSelection_SaysRemove() {
        let model = IngredientListViewModel()
        model.confirmingHide = [Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")]
        model.confirmingDelete = [Ingredient(name: "My Blend")]

        #expect(model.removalConfirmationTitle == "Remove Ingredients?")
    }

    @Test func removalConfirmationMessage_SingleLibraryRow_NamesItAndSaysHidden() {
        let model = IngredientListViewModel()
        model.confirmingHide = [Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")]

        let message = model.removalConfirmationMessage
        #expect(message.contains("\"Olive Oil\""))
        #expect(message.contains("hidden rather than deleted"))
    }

    @Test func removalConfirmationMessage_SeveralLibraryRows_CountsThem() {
        let model = IngredientListViewModel()
        model.confirmingHide = [
            Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil"),
            Ingredient.libraryMock(name: "Coconut Oil", slug: "coconut-oil")
        ]

        #expect(model.removalConfirmationMessage.contains("2 library ingredients"))
    }

    @Test func removalConfirmationMessage_MixedSelection_CoversBothHalves() {
        let model = IngredientListViewModel()
        model.confirmingHide = [Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")]
        model.confirmingDelete = [Ingredient(name: "My Blend")]

        let message = model.removalConfirmationMessage
        #expect(message.contains("hidden rather than deleted"))
        #expect(message.contains("My Blend"))
    }

    @Test func removalConfirmationMessage_NothingStaged_IsEmpty() {
        #expect(IngredientListViewModel().removalConfirmationMessage.isEmpty)
    }

    // MARK: - Category chips

    /// The chip row is built from the unfiltered inventory, so hidden rows have to be
    /// discounted explicitly. A category holding nothing else would otherwise keep a
    /// chip that can only ever lead to "No Results".
    @Test func visibleCategories_EveryRowHidden_DropsTheChip() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: "Oils")
        ctx.insert(oils)
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")
        olive.category = oils
        olive.isHidden = true
        ctx.insert(olive)
        try ctx.save()

        let model = IngredientListViewModel()

        #expect(model.visibleCategories([oils], in: [olive]).isEmpty)
    }

    @Test func visibleCategories_OneRowStillVisible_KeepsTheChip() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: "Oils")
        ctx.insert(oils)
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")
        let coconut = Ingredient.libraryMock(name: "Coconut Oil", slug: "coconut-oil")
        olive.category = oils
        coconut.category = oils
        olive.isHidden = true
        ctx.insert(olive)
        ctx.insert(coconut)
        try ctx.save()

        let model = IngredientListViewModel()

        #expect(model.visibleCategories([oils], in: [olive, coconut]).map(\.name) == ["Oils"])
    }

    /// The pre-existing exception, which the hidden-row filtering must not undo: a
    /// category that is the active filter keeps its chip even when it empties, or the
    /// row reshuffles under the tap that just selected it.
    @Test func visibleCategories_SelectedButEveryRowHidden_KeepsTheChip() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: "Oils")
        ctx.insert(oils)
        let olive = Ingredient.libraryMock(name: "Olive Oil", slug: "olive-oil")
        olive.category = oils
        olive.isHidden = true
        ctx.insert(olive)
        try ctx.save()

        let model = IngredientListViewModel()
        model.toggleCategory(oils)

        #expect(model.visibleCategories([oils], in: [olive]).map(\.name) == ["Oils"])
    }
}

extension Ingredient {
    /// A row as the library installer would have left it.
    static func libraryMock(name: String, slug: String, unit: String = "g") -> Ingredient {
        let ingredient = Ingredient(name: name, unit: unit)
        ingredient.librarySlug = slug
        return ingredient
    }
}
