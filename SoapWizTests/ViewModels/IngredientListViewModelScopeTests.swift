import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Inventory lists what the user owns by default; the rest of the installed
/// library is reached through search and the Whole Library scope (SW-341).
@Suite("IngredientListViewModel — library scope", .serialized)
@MainActor
struct IngredientListViewModelScopeTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private func library(
        _ name: String,
        category: IngredientCategory? = nil,
        remaining: Double? = nil,
        threshold: Double? = nil
    ) -> Ingredient {
        let ingredient = Ingredient(name: name, category: category, unit: "g")
        ingredient.librarySlug = name.lowercased().replacingOccurrences(of: " ", with: "-")
        ingredient.lowStockThreshold = threshold
        if let remaining {
            ingredient.purchases.append(purchase(remaining: remaining))
        }
        return ingredient
    }

    private func purchase(remaining: Double) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: 1000,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        purchase.remainingAmount = remaining
        return purchase
    }

    private func stock(_ ingredients: [Ingredient]) -> StockLevels {
        StockLevels(ingredients.flatMap(\.purchases))
    }

    private func content(_ model: IngredientListViewModel, _ ingredients: [Ingredient]) -> IngredientListContent {
        model.content(for: ingredients, stock: stock(ingredients))
    }

    // MARK: - isOwned

    @Test func isOwned_UserCreated_IsOwned() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let mine = Ingredient(name: "My Blend")
        ctx.insert(mine)

        #expect(IngredientListViewModel().isOwned(mine, stock: stock([mine])))
    }

    @Test func isOwned_LibraryWithPurchase_IsOwned() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = library("Olive Oil", remaining: 500)
        ctx.insert(olive)

        #expect(IngredientListViewModel().isOwned(olive, stock: stock([olive])))
    }

    @Test func isOwned_LibraryWithUsedUpPurchase_IsOwned() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = library("Olive Oil", remaining: 0)
        ctx.insert(olive)

        #expect(IngredientListViewModel().isOwned(olive, stock: stock([olive])))
    }

    @Test func isOwned_LibraryWithCustomChemistry_IsOwned() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = library("Olive Oil")
        olive.hasCustomChemistry = true
        ctx.insert(olive)

        #expect(IngredientListViewModel().isOwned(olive, stock: stock([olive])))
    }

    @Test func isOwned_LibraryFavourite_IsOwned() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = library("Olive Oil")
        olive.isFavorite = true
        ctx.insert(olive)

        #expect(IngredientListViewModel().isOwned(olive, stock: stock([olive])))
    }

    @Test func isOwned_PristineUnboughtLibraryRow_IsNotOwned() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = library("Olive Oil")
        ctx.insert(olive)

        #expect(!IngredientListViewModel().isOwned(olive, stock: stock([olive])))
    }

    // MARK: - Scope

    @Test func content_DefaultScope_HidesUnownedLibraryRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let owned = library("Olive Oil", remaining: 500)
        let unowned = library("Coconut Oil")
        let mine = Ingredient(name: "My Blend")
        [owned, unowned, mine].forEach(ctx.insert)

        let result = content(IngredientListViewModel(), [owned, unowned, mine])

        #expect(Set(result.displayed.map(\.name)) == ["Olive Oil", "My Blend"])
    }

    @Test func content_WholeLibraryScope_ShowsEverything() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let owned = library("Olive Oil", remaining: 500)
        let unowned = library("Coconut Oil")
        [owned, unowned].forEach(ctx.insert)
        let model = IngredientListViewModel()
        model.libraryScope = .all

        #expect(content(model, [owned, unowned]).displayed.count == 2)
    }

    @Test func activeFilterCount_WholeLibrary_CountsAsOneFilter() {
        let model = IngredientListViewModel()
        #expect(model.activeFilterCount == 0)

        model.libraryScope = .all

        #expect(model.activeFilterCount == 1)
        #expect(model.hasActiveFilters)
    }

    @Test func clearFilters_ResetsLibraryScope() {
        let model = IngredientListViewModel()
        model.libraryScope = .all

        model.clearFilters()

        #expect(model.libraryScope == .owned)
        #expect(model.activeFilterCount == 0)
    }

    @Test func trackingOff_ShowsWholeLibraryAndDoesNotCountTheScope() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let owned = library("Olive Oil", remaining: 500)
        let unowned = library("Coconut Oil")
        [owned, unowned].forEach(ctx.insert)
        let model = IngredientListViewModel()
        model.tracksInventory = false

        #expect(content(model, [owned, unowned]).displayed.count == 2)
        #expect(model.activeFilterCount == 0)
        #expect(model.libraryScope == .owned)
    }

    @Test func trackingOff_StoredWholeLibraryChoiceIsRestoredWhenTrackingReturns() {
        let model = IngredientListViewModel()
        model.libraryScope = .all
        model.tracksInventory = false
        #expect(model.activeFilterCount == 0)
        #expect(model.libraryScope == .all)

        model.tracksInventory = true

        #expect(model.activeFilterCount == 1)
    }

    @Test func trackingOff_SearchOffersNoLibraryMatches() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let unowned = library("Coconut Oil")
        ctx.insert(unowned)
        let model = IngredientListViewModel()
        model.tracksInventory = false
        model.searchText = "coco"

        let result = content(model, [unowned])

        #expect(result.libraryMatches.isEmpty)
        #expect(result.displayed.count == 1)
    }

    // MARK: - Summary and counts

    @Test func summary_CountsOnlyInScopeRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let fine = library("Olive Oil", remaining: 900, threshold: 100)
        let low = library("Shea Butter", remaining: 50, threshold: 100)
        let out = library("Castor Oil", remaining: 0)
        let unowned = library("Coconut Oil")
        let all = [fine, low, out, unowned]
        all.forEach(ctx.insert)

        let summary = content(IngredientListViewModel(), all).summary

        #expect(summary.total == 3)
        #expect(summary.low == 1)
        #expect(summary.out == 1)
    }

    @Test func categoryCounts_ExcludeOutOfScopeRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: "Oils")
        ctx.insert(oils)
        let owned = library("Olive Oil", category: oils, remaining: 500)
        let unowned = library("Coconut Oil", category: oils)
        [owned, unowned].forEach(ctx.insert)

        let counts = content(IngredientListViewModel(), [owned, unowned]).categoryCounts

        #expect(counts.all == 1)
        #expect(counts.byCategory[oils.persistentModelID] == 1)
    }

    @Test func visibleCategories_CategoryWithOnlyUnownedRows_GetsNoChip() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: "Oils")
        let waxes = IngredientCategory(name: "Waxes")
        [oils, waxes].forEach(ctx.insert)
        let owned = library("Olive Oil", category: oils, remaining: 500)
        let unowned = library("Beeswax", category: waxes)
        [owned, unowned].forEach(ctx.insert)

        let chips = IngredientListViewModel().visibleCategories([oils, waxes], in: [owned, unowned])

        #expect(chips.map(\.name) == ["Oils"])
    }

    @Test func visibleCategories_UnownedOnlyCategoryStaysWhileSelected() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let waxes = IngredientCategory(name: "Waxes")
        ctx.insert(waxes)
        let unowned = library("Beeswax", category: waxes)
        ctx.insert(unowned)
        let model = IngredientListViewModel()
        model.selectedCategories = [waxes.persistentModelID]

        #expect(model.visibleCategories([waxes], in: [unowned]).map(\.name) == ["Waxes"])
    }

    @Test func visibleCategories_WholeLibrary_GivesUnownedRowsTheirChip() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let waxes = IngredientCategory(name: "Waxes")
        ctx.insert(waxes)
        let unowned = library("Beeswax", category: waxes)
        ctx.insert(unowned)
        let model = IngredientListViewModel()
        model.libraryScope = .all

        #expect(model.visibleCategories([waxes], in: [unowned]).map(\.name) == ["Waxes"])
    }

    // MARK: - Library matches

    @Test func libraryMatches_WithoutSearch_IsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let unowned = library("Coconut Oil")
        ctx.insert(unowned)

        #expect(content(IngredientListViewModel(), [unowned]).libraryMatches.isEmpty)
    }

    @Test func libraryMatches_Searching_ListsMatchingUnownedRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let owned = library("Coconut Milk", remaining: 100)
        let match = library("Coconut Oil")
        let other = library("Olive Oil")
        [owned, match, other].forEach(ctx.insert)
        let model = IngredientListViewModel()
        model.searchText = "coconut"

        let result = content(model, [owned, match, other])

        #expect(result.displayed.map(\.name) == ["Coconut Milk"])
        #expect(result.libraryMatches.map(\.name) == ["Coconut Oil"])
    }

    @Test func libraryMatches_KeepInputOrder() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let first = library("Almond Oil")
        let second = library("Olive Oil")
        [first, second].forEach(ctx.insert)
        let model = IngredientListViewModel()
        model.searchText = "oil"

        #expect(content(model, [first, second]).libraryMatches.map(\.name) == ["Almond Oil", "Olive Oil"])
    }

    @Test func libraryMatches_ExcludeHiddenRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let hidden = library("Coconut Oil")
        hidden.isHidden = true
        ctx.insert(hidden)
        let model = IngredientListViewModel()
        model.searchText = "coconut"

        #expect(content(model, [hidden]).libraryMatches.isEmpty)
    }

    @Test func libraryMatches_NeverAppearInDisplayed() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let owned = library("Coconut Milk", remaining: 100)
        let match = library("Coconut Oil")
        [owned, match].forEach(ctx.insert)
        let model = IngredientListViewModel()
        model.searchText = "coconut"

        let result = content(model, [owned, match])

        let shown = Set(result.displayed.map(\.persistentModelID))
        #expect(result.libraryMatches.allSatisfy { !shown.contains($0.persistentModelID) })
    }

    @Test func libraryMatches_WholeLibraryScope_IsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let match = library("Coconut Oil")
        ctx.insert(match)
        let model = IngredientListViewModel()
        model.libraryScope = .all
        model.searchText = "coconut"

        let result = content(model, [match])

        #expect(result.libraryMatches.isEmpty)
        #expect(result.displayed.map(\.name) == ["Coconut Oil"])
    }

    @Test func libraryMatches_RespectCategorySelection() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: "Oils")
        let waxes = IngredientCategory(name: "Waxes")
        [oils, waxes].forEach(ctx.insert)
        let oil = library("Coconut Oil", category: oils)
        let wax = library("Coconut Wax", category: waxes)
        [oil, wax].forEach(ctx.insert)
        let model = IngredientListViewModel()
        model.searchText = "coconut"
        model.selectedCategories = [waxes.persistentModelID]

        #expect(content(model, [oil, wax]).libraryMatches.map(\.name) == ["Coconut Wax"])
    }

    @Test func ownedCount_CountsOwnedListedRowsWhateverTheScope() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let owned = library("Olive Oil", remaining: 500)
        let unowned = library("Coconut Oil")
        [owned, unowned].forEach(ctx.insert)
        let model = IngredientListViewModel()

        #expect(content(model, [owned, unowned]).ownedCount == 1)
        model.libraryScope = .all
        #expect(content(model, [owned, unowned]).ownedCount == 1)
    }
}
