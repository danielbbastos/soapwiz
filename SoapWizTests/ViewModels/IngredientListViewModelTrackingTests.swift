import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Inventory filtering with stock tracking switched off (SW-81): the stock and
/// expiry filters are ignored rather than cleared, so they come back as they were.
@Suite("IngredientListViewModel — inventory tracking off", .serialized)
@MainActor
struct IngredientListViewModelTrackingTests: IngredientFormTestHelpers {

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

    /// A stock filter set before tracking was switched off must not keep
    /// narrowing a list whose filter menu is no longer shown.
    @Test func trackingOff_StockFilterIsIgnored() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let withStock = Ingredient(name: "A")
        withStock.purchases.append(makePurchase(quantity: 100, remaining: 50))
        let withoutStock = Ingredient(name: "B")
        ctx.insert(withStock); ctx.insert(withoutStock)

        let model = IngredientListViewModel()
        model.stockStatus = .inStock
        model.tracksInventory = false

        #expect(model.filtered([withStock, withoutStock]).count == 2)
        #expect(model.activeFilterCount == 0)
    }

    @Test func trackingOff_ExpiryFilterIsIgnored() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let expired = Ingredient(name: "Expired")
        let pastDate = try #require(Calendar.current.date(byAdding: .day, value: -3, to: .now))
        expired.purchases.append(makePurchase(expiryDate: pastDate))
        let fresh = Ingredient(name: "Fresh")
        ctx.insert(expired); ctx.insert(fresh)

        let model = IngredientListViewModel()
        model.expiryFilter = .expired
        model.tracksInventory = false

        #expect(model.filtered([expired, fresh]).count == 2)
        #expect(!model.hasActiveFilters)
    }

    /// Ignored, not cleared: switching tracking back on restores the filter.
    @Test func trackingBackOn_RestoresStockFilter() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let withStock = Ingredient(name: "A")
        withStock.purchases.append(makePurchase(quantity: 100, remaining: 50))
        let withoutStock = Ingredient(name: "B")
        ctx.insert(withStock); ctx.insert(withoutStock)

        let model = IngredientListViewModel()
        model.stockStatus = .inStock
        model.tracksInventory = false
        model.tracksInventory = true

        #expect(model.filtered([withStock, withoutStock]).map(\.name) == ["A"])
        #expect(model.activeFilterCount == 1)
    }

    @Test func trackingOff_OtherFiltersStillApply() {
        let model = IngredientListViewModel()
        model.searchText = "olive"
        model.tracksInventory = false

        let results = model.filtered([Ingredient(name: "Olive Oil"), Ingredient(name: "Shea Butter")])
        #expect(results.map(\.name) == ["Olive Oil"])
    }
}
