import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Shopping suggestions")
@MainActor
struct ShoppingSuggestionsTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let calendar: Calendar
    private let now: Date

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        self.calendar = calendar
        now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12)))
    }

    private func date(daysFromNow days: Int) throws -> Date {
        try #require(calendar.date(byAdding: .day, value: days, to: now))
    }

    private func makeIngredient(_ name: String = "Olive Oil", threshold: Double? = nil) -> Ingredient {
        let ingredient = Ingredient(name: name, unit: "g")
        ingredient.lowStockThreshold = threshold
        context.insert(ingredient)
        return ingredient
    }

    @discardableResult
    private func addPurchase(
        to ingredient: Ingredient,
        remaining: Double,
        quantity: Double = 1000,
        totalPrice: Double = 10,
        boughtDaysAgo: Int = 10,
        expiry: Date? = nil,
        provider: Provider? = nil
    ) throws -> IngredientPurchase {
        let purchase = IngredientPurchase(
            provider: provider,
            dateOfPurchase: try date(daysFromNow: -boughtDaysAgo),
            quantity: quantity,
            totalPrice: totalPrice,
            badge: "",
            journalCode: "",
            expiryDate: expiry,
            openingDate: nil
        )
        purchase.remainingAmount = remaining
        context.insert(purchase)
        purchase.attach(to: ingredient)
        return purchase
    }

    private func suggestions(
        _ ingredients: [Ingredient],
        listed: Set<PersistentIdentifier> = [],
        tracksInventory: Bool = true
    ) throws -> [ShoppingSuggestion] {
        let purchases = try context.fetch(FetchDescriptor<IngredientPurchase>())
        return ShoppingSuggestions.make(
            ingredients: ingredients,
            purchases: purchases,
            listedIngredientIDs: listed,
            tracksInventory: tracksInventory,
            now: now,
            calendar: calendar
        )
    }

    // MARK: - Reasons

    @Test func make_NoStockLeft_IsOut() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 0)

        let result = try suggestions([ingredient])

        #expect(result.first?.reasons == [.out])
        #expect(result.first?.remaining == 0)
    }

    @Test func make_OutWithoutThreshold_IsStillSuggested() throws {
        let ingredient = makeIngredient(threshold: nil)
        try addPurchase(to: ingredient, remaining: 0)

        #expect(try suggestions([ingredient]).count == 1)
    }

    @Test func make_AtOrBelowThreshold_IsLow() throws {
        let atThreshold = makeIngredient("A", threshold: 100)
        try addPurchase(to: atThreshold, remaining: 100)
        let below = makeIngredient("B", threshold: 100)
        try addPurchase(to: below, remaining: 40)

        let result = try suggestions([atThreshold, below])

        #expect(result.map(\.reasons) == [[.low], [.low]])
    }

    @Test func make_AboveThreshold_IsNotSuggested() throws {
        let ingredient = makeIngredient(threshold: 100)
        try addPurchase(to: ingredient, remaining: 101)

        #expect(try suggestions([ingredient]).isEmpty)
    }

    @Test func make_NilThreshold_IsNotLow() throws {
        let ingredient = makeIngredient(threshold: nil)
        try addPurchase(to: ingredient, remaining: 1)

        #expect(try suggestions([ingredient]).isEmpty)
    }

    @Test func make_StockSpreadAcrossPurchases_SumsRemaining() throws {
        let ingredient = makeIngredient(threshold: 100)
        try addPurchase(to: ingredient, remaining: 60)
        try addPurchase(to: ingredient, remaining: 30)

        let result = try suggestions([ingredient])

        #expect(result.first?.remaining == 90)
        #expect(result.first?.unit == "g")
    }

    @Test func make_ExpiredStockOnHand_IsExpired() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 500, expiry: try date(daysFromNow: -1))

        #expect(try suggestions([ingredient]).first?.reasons == [.expired])
    }

    @Test func make_ExpiringSoon_CarriesDaysUntil() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 500, expiry: try date(daysFromNow: 5))

        #expect(try suggestions([ingredient]).first?.reasons == [.expiring(days: 5)])
    }

    @Test func make_ExpiryUsesTheNearestUpcomingDate() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 500, expiry: try date(daysFromNow: 20))
        try addPurchase(to: ingredient, remaining: 500, expiry: try date(daysFromNow: 7))

        #expect(try suggestions([ingredient]).first?.reasons == [.expiring(days: 7)])
    }

    @Test func make_LowAndExpiring_ListsLowFirst() throws {
        let ingredient = makeIngredient(threshold: 100)
        try addPurchase(to: ingredient, remaining: 50, expiry: try date(daysFromNow: 3))

        #expect(try suggestions([ingredient]).first?.reasons == [.low, .expiring(days: 3)])
    }

    @Test func make_LowAndExpired_ListsExpiredFirstWithoutExpiring() throws {
        let ingredient = makeIngredient(threshold: 100)
        try addPurchase(to: ingredient, remaining: 50, expiry: try date(daysFromNow: -2))
        try addPurchase(to: ingredient, remaining: 0, expiry: try date(daysFromNow: 3))

        #expect(try suggestions([ingredient]).first?.reasons == [.expired, .low])
    }

    @Test func make_OutIgnoresTheExpiryOfUsedUpPurchases() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 0, expiry: try date(daysFromNow: -5))

        #expect(try suggestions([ingredient]).first?.reasons == [.out])
    }

    // MARK: - Expiry window

    @Test func make_ExpiringToday_IsZeroDays() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 500, expiry: now)

        #expect(try suggestions([ingredient]).first?.reasons == [.expiring(days: 0)])
    }

    @Test func make_ExpiringExactlyInOneMonth_IsStillExpiring() throws {
        let ingredient = makeIngredient()
        let cutoff = try #require(calendar.date(byAdding: .month, value: 1, to: now))
        try addPurchase(to: ingredient, remaining: 500, expiry: cutoff)

        #expect(try suggestions([ingredient]).count == 1)
    }

    @Test func make_ExpiringJustPastOneMonth_IsNotSuggested() throws {
        let ingredient = makeIngredient()
        let cutoff = try #require(calendar.date(byAdding: .month, value: 1, to: now))
        try addPurchase(to: ingredient, remaining: 500, expiry: cutoff.addingTimeInterval(1))

        #expect(try suggestions([ingredient]).isEmpty)
    }

    @Test func make_UsedUpPurchaseExpiry_IsIgnored() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 0, expiry: try date(daysFromNow: -30))
        try addPurchase(to: ingredient, remaining: 500)

        #expect(try suggestions([ingredient]).isEmpty)
    }

    // MARK: - Skipped ingredients

    @Test func make_NeverBought_IsSkipped() throws {
        let ingredient = makeIngredient(threshold: 100)

        #expect(try suggestions([ingredient]).isEmpty)
    }

    @Test func make_Hidden_IsSkipped() throws {
        let ingredient = makeIngredient()
        ingredient.isHidden = true
        try addPurchase(to: ingredient, remaining: 0)

        #expect(try suggestions([ingredient]).isEmpty)
    }

    @Test func make_AlreadyListed_IsSkipped() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 0)

        #expect(try suggestions([ingredient], listed: [ingredient.persistentModelID]).isEmpty)
    }

    @Test func make_TrackingOff_ReturnsNothing() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 0)

        #expect(try suggestions([ingredient], tracksInventory: false).isEmpty)
    }

    @Test func make_NoIngredients_ReturnsEmpty() throws {
        #expect(try suggestions([]).isEmpty)
    }

    // MARK: - Dismissal

    @Test func make_Dismissed_StaysHidden() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 0, boughtDaysAgo: 10)
        ingredient.shoppingSuggestionDismissedAt = try date(daysFromNow: -2)

        #expect(try suggestions([ingredient]).isEmpty)
    }

    @Test func make_DismissedThenNewerPurchaseRunsLow_ComesBack() throws {
        let ingredient = makeIngredient(threshold: 100)
        try addPurchase(to: ingredient, remaining: 0, boughtDaysAgo: 10)
        ingredient.shoppingSuggestionDismissedAt = try date(daysFromNow: -5)
        try addPurchase(to: ingredient, remaining: 20, boughtDaysAgo: 1)

        #expect(try suggestions([ingredient]).first?.reasons == [.low])
    }

    @Test func make_PurchaseDatedBeforeDismissal_StaysHidden() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 0, boughtDaysAgo: 10)
        try addPurchase(to: ingredient, remaining: 0, boughtDaysAgo: 4)
        ingredient.shoppingSuggestionDismissedAt = try date(daysFromNow: -2)

        #expect(try suggestions([ingredient]).isEmpty)
    }

    // MARK: - Last supplier and price

    @Test func make_TakesSupplierAndPriceFromTheNewestPurchase() throws {
        let ingredient = makeIngredient()
        let older = Provider(name: "Old Shop")
        let newer = Provider(name: "New Shop")
        context.insert(older)
        context.insert(newer)
        try addPurchase(to: ingredient, remaining: 0, quantity: 100, totalPrice: 5, boughtDaysAgo: 30, provider: older)
        try addPurchase(to: ingredient, remaining: 0, quantity: 200, totalPrice: 20, boughtDaysAgo: 3, provider: newer)

        let result = try #require(try suggestions([ingredient]).first)

        #expect(result.lastSupplierName == "New Shop")
        #expect(result.lastPricePerUnit == 0.1)
    }

    @Test func make_NoProvider_HasNoSupplierName() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 0)

        #expect(try suggestions([ingredient]).first?.lastSupplierName == nil)
    }

    @Test func make_EmptyProviderName_HasNoSupplierName() throws {
        let ingredient = makeIngredient()
        let provider = Provider(name: "")
        context.insert(provider)
        try addPurchase(to: ingredient, remaining: 0, provider: provider)

        #expect(try suggestions([ingredient]).first?.lastSupplierName == nil)
    }

    @Test func make_ZeroQuantityPurchase_HasNoPrice() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 0, quantity: 0, totalPrice: 10)

        #expect(try suggestions([ingredient]).first?.lastPricePerUnit == nil)
    }

    @Test func make_FreePurchase_HasNoPrice() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 0, quantity: 100, totalPrice: 0)

        #expect(try suggestions([ingredient]).first?.lastPricePerUnit == nil)
    }

    // MARK: - Ordering

    @Test func make_OrdersByReasonThenDaysThenName() throws {
        let expiringLate = makeIngredient("Aloe")
        try addPurchase(to: expiringLate, remaining: 500, expiry: try date(daysFromNow: 20))
        let expiringSoon = makeIngredient("Zinc")
        try addPurchase(to: expiringSoon, remaining: 500, expiry: try date(daysFromNow: 2))
        let low = makeIngredient("Mango Butter", threshold: 100)
        try addPurchase(to: low, remaining: 10)
        let expired = makeIngredient("Honey")
        try addPurchase(to: expired, remaining: 500, expiry: try date(daysFromNow: -1))
        let outB = makeIngredient("Beeswax")
        try addPurchase(to: outB, remaining: 0)
        let outA = makeIngredient("Argan Oil")
        try addPurchase(to: outA, remaining: 0)

        let result = try suggestions([expiringLate, expiringSoon, low, expired, outB, outA])

        #expect(result.map(\.ingredient.name) == ["Argan Oil", "Beeswax", "Honey", "Mango Butter", "Zinc", "Aloe"])
    }

    @Test func make_NamesSortNaturally() throws {
        let ten = makeIngredient("Oil 10")
        try addPurchase(to: ten, remaining: 0)
        let two = makeIngredient("Oil 2")
        try addPurchase(to: two, remaining: 0)

        #expect(try suggestions([ten, two]).map(\.ingredient.name) == ["Oil 2", "Oil 10"])
    }

    @Test func make_IdIsTheIngredientsIdentity() throws {
        let ingredient = makeIngredient()
        try addPurchase(to: ingredient, remaining: 0)

        #expect(try suggestions([ingredient]).first?.id == ingredient.persistentModelID)
    }
}
