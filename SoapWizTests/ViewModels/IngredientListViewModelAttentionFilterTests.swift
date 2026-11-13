import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientListViewModel — attention filters")
@MainActor
struct AttentionFilterTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let model = IngredientListViewModel()
    private let now = Date.now

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
    }

    private func day(_ offset: Int) throws -> Date {
        try #require(Calendar.current.date(byAdding: .day, value: offset, to: now))
    }

    private func makeIngredient(
        _ name: String,
        remaining: Double,
        threshold: Double? = nil,
        expiry: Date? = nil,
        totalPrice: Double = 10
    ) -> Ingredient {
        let ingredient = Ingredient(name: name, unit: "g")
        ingredient.lowStockThreshold = threshold
        context.insert(ingredient)
        let purchase = IngredientPurchase(
            dateOfPurchase: now,
            quantity: 1000,
            totalPrice: totalPrice,
            badge: "",
            journalCode: "",
            expiryDate: expiry,
            openingDate: nil
        )
        purchase.remainingAmount = remaining
        context.insert(purchase)
        purchase.attach(to: ingredient)
        return ingredient
    }

    private struct Shelf {
        let out: Ingredient
        let expired: Ingredient
        let low: Ingredient
        let expiring: Ingredient
        let fine: Ingredient

        var all: [Ingredient] { [out, expired, low, expiring, fine] }
    }

    private func makeShelf() throws -> Shelf {
        Shelf(
            out: makeIngredient("Out", remaining: 0),
            expired: makeIngredient("Expired", remaining: 100, expiry: try day(-3)),
            low: makeIngredient("Low", remaining: 50, threshold: 200),
            expiring: makeIngredient("Expiring", remaining: 100, expiry: try day(10)),
            fine: makeIngredient("Fine", remaining: 500)
        )
    }

    private func displayedNames(_ ingredients: [Ingredient]) throws -> Set<String> {
        let purchases = try context.fetch(FetchDescriptor<IngredientPurchase>())
        let content = model.content(for: ingredients, stock: StockLevels(purchases), purchases: purchases, now: now)
        return Set(content.displayed.map(\.name))
    }

    @Test func needsAttention_ListsExactlyTheNeedsAttentionSet() throws {
        let shelf = try makeShelf()
        model.attentionFilter = .needsAttention

        #expect(try displayedNames(shelf.all) == ["Out", "Expired", "Low", "Expiring"])
    }

    @Test func expiringThisMonth_ListsOnlyStockExpiringInTheWindow() throws {
        let shelf = try makeShelf()
        model.attentionFilter = .expiringThisMonth

        #expect(try displayedNames(shelf.all) == ["Expiring"])
    }

    @Test func expiringThisMonth_ListsUnpricedStockExpiringInTheWindow() throws {
        let free = makeIngredient("Free", remaining: 100, expiry: try day(10), totalPrice: 0)
        let fine = makeIngredient("Fine", remaining: 500)
        model.attentionFilter = .expiringThisMonth

        #expect(try displayedNames([free, fine]) == ["Free"])
    }

    @Test func attentionFilter_MatchesNeedsAttentionSets() throws {
        let shelf = try makeShelf()
        let purchases = try context.fetch(FetchDescriptor<IngredientPurchase>())
        let sets = NeedsAttention.ingredientSets(ingredients: shelf.all, purchases: purchases, now: now)

        let stock = StockLevels(purchases)
        model.attentionFilter = .needsAttention
        let attention = Set(model.filtered(shelf.all, stock: stock, purchases: purchases, now: now).map(\.persistentModelID))
        model.attentionFilter = .expiringThisMonth
        let expiring = Set(model.filtered(shelf.all, stock: stock, purchases: purchases, now: now).map(\.persistentModelID))

        #expect(attention == sets.attention)
        #expect(expiring == sets.expiring)
    }

    @Test func attentionFilter_NarrowsCategoryCounts() throws {
        let shelf = try makeShelf()
        let purchases = try context.fetch(FetchDescriptor<IngredientPurchase>())
        model.attentionFilter = .expiringThisMonth

        let content = model.content(for: shelf.all, stock: StockLevels(purchases), purchases: purchases, now: now)
        #expect(content.categoryCounts.all == 1)
    }

    @Test func attentionFilter_TrackingOff_IsIgnored() throws {
        let shelf = try makeShelf()
        model.attentionFilter = .needsAttention
        model.tracksInventory = false

        #expect(try displayedNames(shelf.all).count == 5)
        #expect(model.activeFilterCount == 0)
        #expect(model.effectiveAttentionFilter == nil)
    }

    @Test func attentionFilter_CountsAsOneActiveFilter() {
        #expect(model.activeFilterCount == 0)
        model.attentionFilter = .needsAttention
        #expect(model.activeFilterCount == 1)
        #expect(model.hasActiveFilters)
    }

    @Test func clearFilters_ResetsAttentionFilter() {
        model.attentionFilter = .expiringThisMonth
        model.clearFilters()
        #expect(model.attentionFilter == nil)
    }

    @Test func applyAttentionFilter_ClearsSearchAndEveryOtherFilter() throws {
        let category = IngredientCategory(name: "Oils")
        context.insert(category)
        model.searchText = "olive"
        model.selectedCategories = [category.persistentModelID]
        model.stockStatus = .outOfStock
        model.selectedUnits = [.grams]
        model.expiryFilter = .expired
        model.libraryScope = .all

        model.applyAttentionFilter(.needsAttention)

        #expect(model.searchText.isEmpty)
        #expect(model.selectedCategories.isEmpty)
        #expect(model.stockStatus == .all)
        #expect(model.selectedUnits.isEmpty)
        #expect(model.expiryFilter == .all)
        #expect(model.libraryScope == .owned)
        #expect(model.attentionFilter == .needsAttention)
        #expect(model.activeFilterCount == 1)
    }

    @Test func inStock_IncludesLowStock() throws {
        let shelf = try makeShelf()
        let purchases = try context.fetch(FetchDescriptor<IngredientPurchase>())
        model.stockStatus = .inStock

        let names = Set(model.filtered(shelf.all, stock: StockLevels(purchases)).map(\.name))
        #expect(names == ["Expired", "Low", "Expiring", "Fine"])
    }
}
