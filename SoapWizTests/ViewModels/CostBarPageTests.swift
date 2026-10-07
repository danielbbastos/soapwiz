import Testing
import Foundation
@testable import SoapWiz

@Suite("Cost breakdown bar – pages and summary")
@MainActor
struct CostBarPageTests: RecipeFormTestHelpers {

    /// The whole-batch default followed by one gram size per entry.
    private func makeModel(sizes: [Double]) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.productDrafts = [.wholeBatch()] + sizes.map {
            RecipeProductDraft(size: $0, unitSymbol: ProductUnit.grams.rawValue)
        }
        return model
    }

    // MARK: - Pages

    @Test func costBarPages_TwoSizes_ListsEachSizeThenAddSize() throws {
        let model = makeModel(sizes: [100])
        let ids = model.productDrafts.map(\.id)
        try #require(ids.count == 2)

        #expect(model.costBarPages == [.product(ids[0]), .product(ids[1]), .addSize])
    }

    @Test func costBarPages_NoDrafts_OnlyAddSize() {
        let model = makeModel(sizes: [])
        model.productDrafts = []

        #expect(model.costBarPages == [.addSize])
    }

    @Test func costBarPage_NilScrollID_IsFirstSize() throws {
        let model = makeModel(sizes: [100])
        let first = try #require(model.productDrafts.first)

        #expect(model.costBarPage(for: nil) == .product(first.id))
    }

    @Test func costBarPage_SizeScrollID_IsThatSize() throws {
        let model = makeModel(sizes: [100, 200])
        let ids = model.productDrafts.map(\.id)
        try #require(ids.count == 3)

        #expect(model.costBarPage(for: AnyHashable(ids[2])) == .product(ids[2]))
    }

    @Test func costBarPage_AddSizeScrollID_IsAddSize() {
        let model = makeModel(sizes: [100])

        #expect(model.costBarPage(for: CostBarPage.addSizeID) == .addSize)
    }

    @Test func costBarPage_RemovedSizeScrollID_FallsBackToFirstSize() throws {
        let model = makeModel(sizes: [100])
        let ids = model.productDrafts.map(\.id)
        try #require(ids.count == 2)
        model.removeProduct(id: ids[1])

        #expect(model.costBarPage(for: AnyHashable(ids[1])) == .product(ids[0]))
    }

    @Test func costBarPage_NoDrafts_IsAddSize() {
        let model = makeModel(sizes: [])
        model.productDrafts = []

        #expect(model.costBarPage(for: nil) == .addSize)
    }

    // MARK: - Summary

    @Test func costBarSummary_NoIngredients_AsksForIngredients() {
        let model = RecipeFormViewModel()
        let zero = Double(0).formatted(.currency(code: "EUR"))

        let summary = model.costBarSummary(pvpFactor: 4, currencyCode: "EUR")

        #expect(summary == String(localized: "\(zero) · Add ingredients first"))
    }

    @Test func costBarSummary_PricedOil_ShowsBatchCostAndRRP() throws {
        let model = makeModelWithOils(oils: 1000)
        let oil = try #require(model.oilDrafts.first?.ingredient)
        let purchase = IngredientPurchase(
            dateOfPurchase: .now, quantity: 1000, totalPrice: 8,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
        purchase.ingredient = oil
        let total = model.wholeBatchBreakdown.total
        try #require(total > 0)
        let totalText = total.formatted(.currency(code: "EUR"))
        let rrpText = (total * 3).formatted(.currency(code: "EUR"))

        let summary = model.costBarSummary(pvpFactor: 3, currencyCode: "EUR")

        #expect(summary == String(localized: "Batch \(totalText) · RRP \(rrpText)"))
    }
}
