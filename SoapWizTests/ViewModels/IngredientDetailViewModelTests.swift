import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientDetailViewModel", .serialized)
@MainActor
struct IngredientDetailViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
    }

    private func makePurchase(quantity: Double, daysAgo: Int) throws -> IngredientPurchase {
        let date = try #require(Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now))
        return IngredientPurchase(
            dateOfPurchase: date, quantity: quantity, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
    }

    @Test func sortedPurchasesDescendingByDate() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let older = try makePurchase(quantity: 100, daysAgo: 30)
        let newer = try makePurchase(quantity: 50, daysAgo: 5)
        ctx.insert(older); ctx.insert(newer)
        ingredient.purchases.append(older)
        ingredient.purchases.append(newer)

        let model = IngredientDetailViewModel(ingredient: ingredient)
        #expect(model.sortedPurchases.first === newer)
        #expect(model.sortedPurchases.last === older)
    }

    @Test func totalRemainingSumsAllPurchases() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let purchase1 = try makePurchase(quantity: 100, daysAgo: 10)
        let purchase2 = try makePurchase(quantity: 50, daysAgo: 5)
        ctx.insert(purchase1); ctx.insert(purchase2)
        ingredient.purchases.append(purchase1)
        ingredient.purchases.append(purchase2)

        let model = IngredientDetailViewModel(ingredient: ingredient)
        #expect(model.totalRemaining == 150)
    }

    @Test func deleteByOffsetUsesSortedOrder() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let older = try makePurchase(quantity: 100, daysAgo: 30)
        let newer = try makePurchase(quantity: 50, daysAgo: 5)
        ctx.insert(older); ctx.insert(newer)
        ingredient.purchases.append(older)
        ingredient.purchases.append(newer)
        try ctx.save()

        let model = IngredientDetailViewModel(ingredient: ingredient)
        model.delete(at: IndexSet(integer: 0), context: ctx)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<IngredientPurchase>())
        #expect(remaining.count == 1)
        #expect(remaining.first === older)
    }

    // MARK: - Purchases preview (SW-153)

    @Test func hasMorePurchases_TwoOrFewer_IsFalse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        for daysAgo in [10, 5] {
            let purchase = try makePurchase(quantity: 100, daysAgo: daysAgo)
            ctx.insert(purchase)
            ingredient.purchases.append(purchase)
        }
        #expect(IngredientDetailViewModel(ingredient: ingredient).hasMorePurchases == false)
    }

    @Test func hasMorePurchases_MoreThanTwo_IsTrue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        for daysAgo in [15, 10, 5] {
            let purchase = try makePurchase(quantity: 100, daysAgo: daysAgo)
            ctx.insert(purchase)
            ingredient.purchases.append(purchase)
        }
        #expect(IngredientDetailViewModel(ingredient: ingredient).hasMorePurchases)
    }

    @Test func displayedPurchases_Collapsed_ShowsTheTwoNewest() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let oldest = try makePurchase(quantity: 10, daysAgo: 30)
        let middle = try makePurchase(quantity: 20, daysAgo: 15)
        let newest = try makePurchase(quantity: 30, daysAgo: 2)
        for purchase in [oldest, middle, newest] {
            ctx.insert(purchase)
            ingredient.purchases.append(purchase)
        }

        let model = IngredientDetailViewModel(ingredient: ingredient)
        let collapsed = model.displayedPurchases(showingAll: false)
        #expect(collapsed.count == 2)
        #expect(collapsed.first === newest)
        #expect(collapsed.last === middle)
    }

    @Test func displayedPurchases_Expanded_ShowsAll() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        for daysAgo in [30, 15, 2] {
            let purchase = try makePurchase(quantity: 100, daysAgo: daysAgo)
            ctx.insert(purchase)
            ingredient.purchases.append(purchase)
        }

        let model = IngredientDetailViewModel(ingredient: ingredient)
        #expect(model.displayedPurchases(showingAll: true).count == 3)
    }

    // MARK: - Chemistry gating (SW-153)

    @Test func showsChemistry_OilCategory_IsTrue() {
        let ing = Ingredient.mockOil(name: "Olive", naohSap: 0.134, oleic: 69)
        ing.category = IngredientCategory(name: IngredientCategory.Name.oils)
        let model = IngredientDetailViewModel(ingredient: ing)
        #expect(model.showsChemistry)
        #expect(model.chemistryStats != nil)
    }

    @Test func showsChemistry_NonOilCategory_IsFalse() {
        let ing = Ingredient(name: "Sodium Hydroxide", unit: "g")
        ing.category = IngredientCategory(name: IngredientCategory.Name.lyes)
        let model = IngredientDetailViewModel(ingredient: ing)
        #expect(model.showsChemistry == false)
        #expect(model.chemistryStats == nil)
    }

    @Test func showsChemistry_NoCategory_IsFalse() {
        let model = IngredientDetailViewModel(ingredient: Ingredient(name: "Mystery", unit: "g"))
        #expect(model.showsChemistry == false)
        #expect(model.chemistryStats == nil)
    }

    // MARK: - Profile presence (SW-153)

    @Test func hasFattyAcidProfile_RealProfile_IsTrue() {
        let ing = Ingredient.mockOil(name: "Olive", naohSap: 0.134, palmitic: 14, oleic: 69)
        ing.category = IngredientCategory(name: IngredientCategory.Name.oils)
        #expect(IngredientDetailViewModel(ingredient: ing).hasFattyAcidProfile)
    }

    /// An all-zero profile is "not specified" rather than a genuine all-zero oil,
    /// so the composition sections give way to a note instead of a page of 0.00 %.
    @Test func hasFattyAcidProfile_AllZeroProfile_IsFalse() {
        let ing = Ingredient.mockOil(name: "Custom", naohSap: 0.19)
        ing.category = IngredientCategory(name: IngredientCategory.Name.oils)
        #expect(IngredientDetailViewModel(ingredient: ing).hasFattyAcidProfile == false)
    }

    @Test func hasFattyAcidProfile_NoProfileAtAll_IsFalse() {
        let ing = Ingredient(name: "Custom Oil", unit: "g")
        ing.sapValue = 0.19
        ing.category = IngredientCategory(name: IngredientCategory.Name.oils)
        #expect(IngredientDetailViewModel(ingredient: ing).hasFattyAcidProfile == false)
    }

    // MARK: - Single-ingredient stats reproduce the ingredient's own chemistry (SW-153)

    @Test func chemistryStats_ReproducesTheProfile() throws {
        let ing = Ingredient.mockOil(name: "Olive", naohSap: 0.134, palmitic: 14, oleic: 69)
        ing.category = IngredientCategory(name: IngredientCategory.Name.oils)
        let stats = try #require(IngredientDetailViewModel(ingredient: ing).chemistryStats)
        #expect(stats.fattyAcidProfile.palmitic == 14)
        #expect(stats.fattyAcidProfile.oleic == 69)
    }

    @Test func chemistryStats_ReproducesNaOHAndKOHSap() throws {
        let ing = Ingredient.mockOil(name: "Olive", naohSap: 0.134, kohSap: 0.188, oleic: 69)
        ing.category = IngredientCategory(name: IngredientCategory.Name.oils)
        let stats = try #require(IngredientDetailViewModel(ingredient: ing).chemistryStats)
        #expect(abs(try #require(stats.totalNaOHSap) - 0.134) < 0.0001)
        #expect(abs(try #require(stats.totalKOHSap) - 0.188) < 0.0001)
    }

    @Test func chemistryStats_INSMatchesTheDerivedValue() throws {
        let ing = Ingredient.mockOil(name: "Olive", naohSap: 0.134, oleic: 69)
        ing.category = IngredientCategory(name: IngredientCategory.Name.oils)
        let stats = try #require(IngredientDetailViewModel(ingredient: ing).chemistryStats)
        let profile = try #require(ing.fattyAcidProfile)
        let expected = FattyAcidProfile.ins(naOHSapFactor: 0.134, iodineValue: profile.iodineValue)
        #expect(abs(try #require(stats.ins) - expected) < 0.0001)
    }

    /// An oil with SAP but no profile still yields stats — the SAP & INS rows
    /// stand alone while the composition is replaced by a note.
    @Test func chemistryStats_OilWithoutProfile_StillReportsSAPAndINS() throws {
        let ing = Ingredient(name: "Custom Oil", unit: "g")
        ing.sapValue = 0.19
        ing.category = IngredientCategory(name: IngredientCategory.Name.oils)
        let model = IngredientDetailViewModel(ingredient: ing)
        let stats = try #require(model.chemistryStats)
        #expect(model.hasFattyAcidProfile == false)
        #expect(abs(try #require(stats.totalNaOHSap) - 0.19) < 0.0001)
        // Iodine is zero without a profile, so INS collapses to SAP × 1402.5.
        #expect(abs(try #require(stats.ins) - 0.19 * 1402.5) < 0.0001)
    }
}
