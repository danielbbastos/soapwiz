import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import SoapWiz

@Suite("IngredientListViewModel — filtering", .serialized)
@MainActor
struct IngredientListViewModelFilterTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
    }

    private func makePurchase(quantity: Double = 100, remaining: Double? = nil, expiryDate: Date? = nil) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: quantity,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: expiryDate,
            openingDate: nil
        )
        if let remaining {
            purchase.remainingAmount = remaining
        }
        return purchase
    }

    // MARK: - No filters

    @Test func noFiltersReturnsAll() {
        let model = IngredientListViewModel()
        #expect(model.filtered([Ingredient(name: "A"), Ingredient(name: "B")]).count == 2)
    }

    // MARK: - Search

    @Test func searchFiltersByNameCaseInsensitive() {
        let olive = Ingredient(name: "Olive Oil")
        let coconut = Ingredient(name: "Coconut Oil")
        let model = IngredientListViewModel()
        model.searchText = "olive"
        let results = model.filtered([olive, coconut])
        #expect(results.count == 1)
        #expect(results.first?.name == "Olive Oil")
    }

    @Test func searchPartialMatch() {
        let model = IngredientListViewModel()
        model.searchText = "oil"
        #expect(model.filtered([Ingredient(name: "Olive Oil"), Ingredient(name: "Coconut Oil")]).count == 2)
    }

    @Test func searchNoMatchReturnsEmpty() {
        let model = IngredientListViewModel()
        model.searchText = "xyz"
        #expect(model.filtered([Ingredient(name: "Olive Oil")]).isEmpty)
    }

    // MARK: - Category filter

    @Test func categoryFilterIncludesMatchingIngredients() throws {
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
        model.selectedCategories = [oils.persistentModelID]
        let results = model.filtered([olive, naoh])
        #expect(results.count == 1)
        #expect(results.first?.name == "Olive Oil")
    }

    @Test func categoryFilterExcludesIngredientWithNoCategory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        ctx.insert(oils)
        let olive = Ingredient(name: "Olive Oil", category: oils)
        let mystery = Ingredient(name: "Mystery")
        ctx.insert(olive); ctx.insert(mystery)
        try ctx.save()

        let model = IngredientListViewModel()
        model.selectedCategories = [oils.persistentModelID]
        let results = model.filtered([olive, mystery])
        #expect(results.count == 1)
        #expect(results.first?.name == "Olive Oil")
    }

    @Test func categoryFilterMultipleSelections() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        let lyes = IngredientCategory(name: "Lyes")
        ctx.insert(oils); ctx.insert(lyes)
        let olive = Ingredient(name: "Olive Oil", category: oils)
        let naoh = Ingredient(name: "NaOH", category: lyes)
        let fragrance = Ingredient(name: "Fragrance")
        ctx.insert(olive); ctx.insert(naoh); ctx.insert(fragrance)
        try ctx.save()

        let model = IngredientListViewModel()
        model.selectedCategories = [oils.persistentModelID, lyes.persistentModelID]
        let results = model.filtered([olive, naoh, fragrance])
        #expect(results.count == 2)
    }

    // MARK: - Stock status filter

    @Test func stockFilterInStock() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let withStock = Ingredient(name: "A")
        withStock.purchases.append(makePurchase(quantity: 100, remaining: 50))
        let withoutStock = Ingredient(name: "B")
        ctx.insert(withStock); ctx.insert(withoutStock)

        let model = IngredientListViewModel()
        model.stockStatus = .inStock
        let results = model.filtered([withStock, withoutStock])
        #expect(results.count == 1)
        #expect(results.first?.name == "A")
    }

    @Test func stockFilterInStockExcludesLowStock() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let lowStock = Ingredient(name: "A")
        lowStock.lowStockThreshold = 30
        lowStock.purchases.append(makePurchase(quantity: 100, remaining: 20))
        ctx.insert(lowStock)

        let model = IngredientListViewModel()
        model.stockStatus = .inStock
        #expect(model.filtered([lowStock]).isEmpty)
    }

    @Test func stockFilterOutOfStock() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let depleted = Ingredient(name: "A")
        depleted.purchases.append(makePurchase(quantity: 100, remaining: 0))
        let withStock = Ingredient(name: "B")
        withStock.purchases.append(makePurchase(quantity: 100, remaining: 50))
        ctx.insert(depleted); ctx.insert(withStock)

        let model = IngredientListViewModel()
        model.stockStatus = .outOfStock
        let results = model.filtered([depleted, withStock])
        #expect(results.count == 1)
        #expect(results.first?.name == "A")
    }

    @Test func stockFilterLowStock() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let lowStock = Ingredient(name: "A")
        lowStock.lowStockThreshold = 30
        lowStock.purchases.append(makePurchase(quantity: 100, remaining: 20))
        let wellStocked = Ingredient(name: "B")
        wellStocked.purchases.append(makePurchase(quantity: 100, remaining: 80))
        ctx.insert(lowStock); ctx.insert(wellStocked)

        let model = IngredientListViewModel()
        model.stockStatus = .lowStock
        let results = model.filtered([lowStock, wellStocked])
        #expect(results.count == 1)
        #expect(results.first?.name == "A")
    }

    // MARK: - Unit filter

    @Test func unitFilterIncludesMatchingIngredients() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let water = Ingredient(name: "Water", unit: "ml")
        ctx.insert(olive); ctx.insert(water)
        try ctx.save()

        let model = IngredientListViewModel()
        model.selectedUnits = [.grams]
        let results = model.filtered([olive, water])
        #expect(results.count == 1)
        #expect(results.first?.name == "Olive Oil")
    }

    // MARK: - Expiry filter

    @Test func expiryFilterExpiringSoon() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let soon = try #require(Calendar.current.date(byAdding: .day, value: 15, to: .now))
        let far = try #require(Calendar.current.date(byAdding: .year, value: 2, to: .now))
        let expiringSoon = Ingredient(name: "A")
        expiringSoon.purchases.append(makePurchase(expiryDate: soon))
        let expiringLater = Ingredient(name: "B")
        expiringLater.purchases.append(makePurchase(expiryDate: far))
        ctx.insert(expiringSoon); ctx.insert(expiringLater)

        let model = IngredientListViewModel()
        model.expiryFilter = .expiringSoon
        let results = model.filtered([expiringSoon, expiringLater])
        #expect(results.count == 1)
        #expect(results.first?.name == "A")
    }

    @Test func expiryFilterExpired() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let past = try #require(Calendar.current.date(byAdding: .day, value: -1, to: .now))
        let future = try #require(Calendar.current.date(byAdding: .year, value: 1, to: .now))
        let expired = Ingredient(name: "A")
        expired.purchases.append(makePurchase(expiryDate: past))
        let notExpired = Ingredient(name: "B")
        notExpired.purchases.append(makePurchase(expiryDate: future))
        ctx.insert(expired); ctx.insert(notExpired)

        let model = IngredientListViewModel()
        model.expiryFilter = .expired
        let results = model.filtered([expired, notExpired])
        #expect(results.count == 1)
        #expect(results.first?.name == "A")
    }

    @Test func expiryFilterNoExpiry() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let future = try #require(Calendar.current.date(byAdding: .year, value: 1, to: .now))
        let noExpiry = Ingredient(name: "A")
        noExpiry.purchases.append(makePurchase(expiryDate: nil))
        let hasExpiry = Ingredient(name: "B")
        hasExpiry.purchases.append(makePurchase(expiryDate: future))
        ctx.insert(noExpiry); ctx.insert(hasExpiry)

        let model = IngredientListViewModel()
        model.expiryFilter = .noExpiry
        let results = model.filtered([noExpiry, hasExpiry])
        #expect(results.count == 1)
        #expect(results.first?.name == "A")
    }

    @Test func expiryFilterNoExpiryMatchesIngredientWithNoPurchases() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let noPurchases = Ingredient(name: "A")
        ctx.insert(noPurchases)

        let model = IngredientListViewModel()
        model.expiryFilter = .noExpiry
        #expect(model.filtered([noPurchases]).count == 1)
    }

    // MARK: - Combined filters

    @Test func searchAndCategoryFilterCombined() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        ctx.insert(oils)
        let olive = Ingredient(name: "Olive Oil", category: oils)
        let coconut = Ingredient(name: "Coconut Oil", category: oils)
        let naoh = Ingredient(name: "NaOH")
        ctx.insert(olive); ctx.insert(coconut); ctx.insert(naoh)
        try ctx.save()

        let model = IngredientListViewModel()
        model.searchText = "olive"
        model.selectedCategories = [oils.persistentModelID]
        let results = model.filtered([olive, coconut, naoh])
        #expect(results.count == 1)
        #expect(results.first?.name == "Olive Oil")
    }

    // MARK: - hasActiveFilters / activeFilterCount / clearFilters

    @Test func hasActiveFiltersIsFalseByDefault() {
        let model = IngredientListViewModel()
        #expect(!model.hasActiveFilters)
    }

    @Test func hasActiveFiltersIsTrueWhenAnyFilterSet() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        ctx.insert(oils)
        try ctx.save()

        let model = IngredientListViewModel()
        model.selectedCategories = [oils.persistentModelID]
        #expect(model.hasActiveFilters)
    }

    @Test func activeFilterCountTracksEachDimension() {
        let model = IngredientListViewModel()
        #expect(model.activeFilterCount == 0)

        model.stockStatus = .inStock
        #expect(model.activeFilterCount == 1)

        model.expiryFilter = .expired
        #expect(model.activeFilterCount == 2)

        model.clearFilters()
        #expect(model.activeFilterCount == 0)
    }

    @Test func clearFiltersResetsAll() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        ctx.insert(oils)
        try ctx.save()

        let model = IngredientListViewModel()
        model.selectedCategories = [oils.persistentModelID]
        model.stockStatus = .lowStock
        model.expiryFilter = .expired
        model.clearFilters()

        #expect(!model.hasActiveFilters)
        #expect(model.stockStatus == .all)
        #expect(model.expiryFilter == .all)
        #expect(model.selectedCategories.isEmpty)
    }

    // MARK: - Pruning selections after a duplicate merge

    /// `DuplicateMerger` deletes the losing row of a duplicate pair. A filter still
    /// holding that ID would match no ingredient and silently show an empty list.
    @Test func pruneSelectedCategoriesDropsIDsThatNoLongerExist() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let survivor = IngredientCategory(name: "Oils")
        let merged = IngredientCategory(name: "oils")
        ctx.insert(survivor)
        ctx.insert(merged)
        try ctx.save()

        let model = IngredientListViewModel()
        model.selectedCategories = [survivor.persistentModelID, merged.persistentModelID]

        model.pruneSelectedCategories(against: [survivor])

        #expect(model.selectedCategories == [survivor.persistentModelID])
    }

    @Test func pruneSelectedCategoriesKeepsStillValidSelections() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        let waxes = IngredientCategory(name: "Waxes")
        ctx.insert(oils)
        ctx.insert(waxes)
        try ctx.save()

        let model = IngredientListViewModel()
        model.selectedCategories = [oils.persistentModelID, waxes.persistentModelID]

        model.pruneSelectedCategories(against: [oils, waxes])

        #expect(model.selectedCategories.count == 2)
    }

    /// An empty selection means "all categories" — pruning must not turn that into
    /// a filter that matches nothing.
    @Test func pruneSelectedCategoriesLeavesAnEmptySelectionAlone() throws {
        let model = IngredientListViewModel()

        model.pruneSelectedCategories(against: [])

        #expect(model.selectedCategories.isEmpty)
        #expect(!model.hasActiveFilters)
    }
}
