import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Needs attention")
@MainActor
struct NeedsAttentionTests {

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

    private func makeIngredient(_ name: String = "Olive Oil", threshold: Double? = nil, hidden: Bool = false) -> Ingredient {
        let ingredient = Ingredient(name: name, unit: "g")
        ingredient.lowStockThreshold = threshold
        ingredient.isHidden = hidden
        context.insert(ingredient)
        return ingredient
    }

    @discardableResult
    private func addPurchase(
        to ingredient: Ingredient,
        remaining: Double,
        quantity: Double = 1000,
        totalPrice: Double = 20,
        expiry: Date? = nil
    ) throws -> IngredientPurchase {
        let purchase = IngredientPurchase(
            dateOfPurchase: try date(daysFromNow: -10),
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

    private func attention(
        _ ingredients: [Ingredient],
        tracksInventory: Bool = true,
        rowLimit: Int = 4
    ) throws -> NeedsAttention? {
        let purchases = try context.fetch(FetchDescriptor<IngredientPurchase>())
        return NeedsAttention.make(
            ingredients: ingredients,
            purchases: purchases,
            tracksInventory: tracksInventory,
            now: now,
            calendar: calendar,
            rowLimit: rowLimit
        )
    }

    // MARK: - Value at risk

    @Test func valueAtRisk_ExpiredWithStock_Counts() throws {
        let oil = makeIngredient()
        try addPurchase(to: oil, remaining: 250, expiry: try date(daysFromNow: -5))
        let result = try #require(try attention([oil]))
        #expect(abs(result.valueAtRisk - 5) < 0.0001)
    }

    @Test func valueAtRisk_ExpiringWithinMonth_Counts() throws {
        let oil = makeIngredient()
        try addPurchase(to: oil, remaining: 500, expiry: try date(daysFromNow: 20))
        let result = try #require(try attention([oil]))
        #expect(abs(result.valueAtRisk - 10) < 0.0001)
    }

    @Test func valueAtRisk_ExpiringBeyondMonth_Excluded() throws {
        let oil = makeIngredient()
        try addPurchase(to: oil, remaining: 500, expiry: try date(daysFromNow: 60))
        #expect(try attention([oil]) == nil)
    }

    @Test func valueAtRisk_UsedUpExpiredPurchase_Excluded() throws {
        let oil = makeIngredient()
        try addPurchase(to: oil, remaining: 0, expiry: try date(daysFromNow: -5))
        let result = try #require(try attention([oil]))
        #expect(result.valueAtRisk == 0)
    }

    @Test func valueAtRisk_HiddenIngredient_Excluded() throws {
        let oil = makeIngredient(hidden: true)
        try addPurchase(to: oil, remaining: 250, expiry: try date(daysFromNow: -5))
        #expect(try attention([oil]) == nil)
    }

    // MARK: - Ranking

    @Test func rows_RankOutExpiredLowExpiring() throws {
        let expiringLate = makeIngredient("Expiring Late")
        try addPurchase(to: expiringLate, remaining: 100, expiry: try date(daysFromNow: 20))
        let expiringSoon = makeIngredient("Expiring Soon")
        try addPurchase(to: expiringSoon, remaining: 100, expiry: try date(daysFromNow: 5))
        let low = makeIngredient("Low", threshold: 500)
        try addPurchase(to: low, remaining: 100)
        let expired = makeIngredient("Expired")
        try addPurchase(to: expired, remaining: 100, expiry: try date(daysFromNow: -3))
        let out = makeIngredient("Out")
        try addPurchase(to: out, remaining: 0)

        let result = try #require(try attention([expiringLate, expiringSoon, low, expired, out]))
        #expect(result.rows.map(\.ingredient.name) == ["Out", "Expired", "Low", "Expiring Soon"])
        #expect(result.moreCount == 1)
    }

    @Test func rows_SameReason_TiesByName() throws {
        let beta = makeIngredient("Beta")
        try addPurchase(to: beta, remaining: 0)
        let alpha = makeIngredient("Alpha")
        try addPurchase(to: alpha, remaining: 0)

        let result = try #require(try attention([beta, alpha]))
        #expect(result.rows.map(\.ingredient.name) == ["Alpha", "Beta"])
    }

    @Test func rows_UsedUpPurchaseExpiry_CreatesNoExpiryRow() throws {
        let oil = makeIngredient()
        try addPurchase(to: oil, remaining: 0, expiry: try date(daysFromNow: -5))
        try addPurchase(to: oil, remaining: 300, expiry: try date(daysFromNow: 90))

        #expect(try attention([oil]) == nil)
    }

    @Test func rows_UsedUpOnly_IsOutNotExpired() throws {
        let oil = makeIngredient()
        try addPurchase(to: oil, remaining: 0, expiry: try date(daysFromNow: -5))
        let result = try #require(try attention([oil]))
        #expect(result.rows.map(\.reason) == [.out])
        #expect(result.rows.first?.earliestExpired == nil)
    }

    // MARK: - Cap

    @Test func rows_SixQualifying_ShowsFourAndCountsTwoMore() throws {
        let ingredients = try (0..<6).map { index -> Ingredient in
            let ingredient = makeIngredient("Item \(index)")
            try addPurchase(to: ingredient, remaining: 0)
            return ingredient
        }
        let result = try #require(try attention(ingredients))
        #expect(result.rows.count == 4)
        #expect(result.moreCount == 2)
    }

    // MARK: - Time

    @Test func make_LaterNow_TurnsExpiringIntoExpired() throws {
        let oil = makeIngredient()
        try addPurchase(to: oil, remaining: 500, expiry: try date(daysFromNow: 1))
        let purchases = try context.fetch(FetchDescriptor<IngredientPurchase>())

        let before = try #require(
            NeedsAttention.make(ingredients: [oil], purchases: purchases, tracksInventory: true, now: now, calendar: calendar)
        )
        #expect(before.rows.first?.stamp == .expiresIn(days: 1))

        let after = try #require(
            NeedsAttention.make(
                ingredients: [oil],
                purchases: purchases,
                tracksInventory: true,
                now: try date(daysFromNow: 2),
                calendar: calendar
            )
        )
        #expect(after.rows.first?.stamp == .expired)
        #expect(abs(after.valueAtRisk - 10) < 0.0001)
    }

    // MARK: - Nil

    @Test func make_TrackingOff_ReturnsNil() throws {
        let oil = makeIngredient()
        try addPurchase(to: oil, remaining: 0, expiry: try date(daysFromNow: -5))
        #expect(try attention([oil], tracksInventory: false) == nil)
    }

    @Test func make_NothingQualifies_ReturnsNil() throws {
        let oil = makeIngredient()
        try addPurchase(to: oil, remaining: 500, expiry: try date(daysFromNow: 90))
        #expect(try attention([oil]) == nil)
    }

    // MARK: - Row details

    @Test func row_Expiring_MapsToExpiresInStamp() throws {
        let oil = makeIngredient()
        try addPurchase(to: oil, remaining: 100, expiry: try date(daysFromNow: 9))
        let row = try #require(try attention([oil])?.rows.first)
        #expect(row.reason == .expiring(days: 9))
        #expect(row.stamp == .expiresIn(days: 9))
    }

    @Test func row_Expired_CarriesEarliestExpiryAndShare() throws {
        let oil = makeIngredient()
        let earliest = try date(daysFromNow: -10)
        try addPurchase(to: oil, remaining: 250, expiry: earliest)
        try addPurchase(to: oil, remaining: 100, expiry: try date(daysFromNow: -2))
        let row = try #require(try attention([oil])?.rows.first)
        #expect(row.stamp == .expired)
        #expect(row.earliestExpired == earliest)
        #expect(abs(row.valueAtRisk - 7) < 0.0001)
        #expect(row.remaining == 350)
    }

    @Test func row_Out_CarriesSupplierName() throws {
        let oil = makeIngredient()
        let provider = Provider(name: "Acme", website: "", notes: "")
        context.insert(provider)
        let purchase = try addPurchase(to: oil, remaining: 0)
        purchase.provider = provider
        let row = try #require(try attention([oil])?.rows.first)
        #expect(row.stamp == .out)
        #expect(row.supplierName == "Acme")
    }
}
