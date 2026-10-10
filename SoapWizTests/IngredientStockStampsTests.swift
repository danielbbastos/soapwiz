import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Ingredient stock stamps")
@MainActor
struct IngredientStockStampsTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let calendar: Calendar
    private let now: Date

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        self.calendar = calendar
        now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12)))
    }

    private func day(_ offset: Int) throws -> Date {
        try #require(calendar.date(byAdding: .day, value: offset, to: now))
    }

    private func makeIngredient(
        threshold: Double? = nil,
        purchases: [(remaining: Double, expiry: Date?)]
    ) -> Ingredient {
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.lowStockThreshold = threshold
        context.insert(ingredient)
        for entry in purchases {
            let purchase = IngredientPurchase(
                dateOfPurchase: now,
                quantity: 1000,
                totalPrice: 10,
                badge: "",
                journalCode: "",
                expiryDate: entry.expiry,
                openingDate: nil
            )
            purchase.remainingAmount = entry.remaining
            ingredient.purchases.append(purchase)
        }
        return ingredient
    }

    private func stamps(for ingredient: Ingredient, tracksInventory: Bool = true) -> [IngredientStockStamp] {
        IngredientStockStamp.stamps(for: ingredient, tracksInventory: tracksInventory, now: now, calendar: calendar)
    }

    @Test func stamps_PlainStockedIngredient_ReturnsNone() {
        let ingredient = makeIngredient(threshold: 100, purchases: [(500, nil)])

        #expect(stamps(for: ingredient).isEmpty)
    }

    @Test func stamps_InventoryNotTracked_ReturnsNone() {
        let ingredient = makeIngredient(purchases: [(0, nil)])

        #expect(stamps(for: ingredient, tracksInventory: false).isEmpty)
    }

    @Test func stamps_NeverBoughtWithThreshold_ReturnsNone() {
        let ingredient = makeIngredient(threshold: 100, purchases: [])

        #expect(stamps(for: ingredient).isEmpty)
    }

    @Test func stamps_PurchasesAllUsedUp_ReturnsOut() {
        let ingredient = makeIngredient(purchases: [(0, nil)])

        #expect(stamps(for: ingredient) == [.out])
    }

    @Test func stamps_AtThreshold_ReturnsLow() {
        let ingredient = makeIngredient(threshold: 100, purchases: [(100, nil)])

        #expect(stamps(for: ingredient) == [.low])
    }

    @Test func stamps_AboveThreshold_ReturnsNone() {
        let ingredient = makeIngredient(threshold: 100, purchases: [(101, nil)])

        #expect(stamps(for: ingredient).isEmpty)
    }

    @Test func stamps_OutAndBelowThreshold_OutSupersedesLow() {
        let ingredient = makeIngredient(threshold: 100, purchases: [(0, nil)])

        #expect(stamps(for: ingredient) == [.out])
    }

    @Test func stamps_ExpiredPurchase_ReturnsExpired() throws {
        let ingredient = makeIngredient(purchases: [(500, try day(-1))])

        #expect(stamps(for: ingredient) == [.expired])
    }

    @Test func stamps_ExpiryInTenDays_ReturnsExpiresInTenDays() throws {
        let ingredient = makeIngredient(purchases: [(500, try day(10))])

        #expect(stamps(for: ingredient) == [.expiresIn(days: 10)])
    }

    @Test func stamps_ExpiryLaterToday_ReturnsExpiresInZeroDays() throws {
        let laterToday = try #require(calendar.date(byAdding: .hour, value: 3, to: now))
        let ingredient = makeIngredient(purchases: [(500, laterToday)])

        #expect(stamps(for: ingredient) == [.expiresIn(days: 0)])
    }

    @Test func stamps_ExpiryBeyondAMonth_ReturnsNone() throws {
        let beyond = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.date(byAdding: .month, value: 1, to: now) ?? now))
        let ingredient = makeIngredient(purchases: [(500, beyond)])

        #expect(stamps(for: ingredient).isEmpty)
    }

    @Test func stamps_ExpiredAndAnotherExpiringSoon_ReturnsOnlyExpired() throws {
        let ingredient = makeIngredient(purchases: [(250, try day(-3)), (250, try day(5))])

        #expect(stamps(for: ingredient) == [.expired])
    }

    @Test func stamps_LowAndExpiring_ReturnsLowThenExpiresIn() throws {
        let ingredient = makeIngredient(threshold: 600, purchases: [(500, try day(7))])

        #expect(stamps(for: ingredient) == [.low, .expiresIn(days: 7)])
    }

    @Test func stamps_OutAndExpiredAndExpiring_ReturnsAtMostTwoInUrgencyOrder() throws {
        let ingredient = makeIngredient(threshold: 100, purchases: [(0, try day(-2)), (0, try day(5))])

        #expect(stamps(for: ingredient) == [.out, .expired])
    }

    @Test func word_ExpiresInZeroDays_DiffersFromExpiresInSeveral() {
        #expect(IngredientStockStamp.expiresIn(days: 0).word != IngredientStockStamp.expiresIn(days: 3).word)
    }

    @Test func tone_AndGlyph_FollowUrgency() {
        #expect(IngredientStockStamp.out.tone == .danger)
        #expect(IngredientStockStamp.expired.tone == .danger)
        #expect(IngredientStockStamp.low.tone == .warning)
        #expect(IngredientStockStamp.expiresIn(days: 4).tone == .warning)
        #expect(IngredientStockStamp.out.glyph == IngredientStockStamp.low.glyph)
        #expect(IngredientStockStamp.expired.glyph == IngredientStockStamp.expiresIn(days: 4).glyph)
    }
}
