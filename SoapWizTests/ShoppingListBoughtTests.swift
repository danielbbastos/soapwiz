import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Shopping list bought")
@MainActor
struct ShoppingListBoughtTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let calendar: Calendar
    private let created = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        self.calendar = calendar
    }

    private func day(_ offset: Int) throws -> Date {
        try #require(calendar.date(byAdding: .day, value: offset, to: created))
    }

    private func startOfCreationDay() -> Date {
        calendar.startOfDay(for: created)
    }

    private func makeIngredient(_ name: String = "Olive Oil") -> Ingredient {
        let ingredient = Ingredient(name: name, unit: "g")
        context.insert(ingredient)
        return ingredient
    }

    private func makeItem(_ name: String = "Olive Oil", ingredient: Ingredient?) -> ShoppingListItem {
        let item = ShoppingListItem(name: name, ingredient: ingredient)
        item.createdAt = created
        context.insert(item)
        return item
    }

    private func makePurchase(of ingredient: Ingredient, on date: Date) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            provider: nil,
            dateOfPurchase: date,
            quantity: 100,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        context.insert(purchase)
        purchase.attach(to: ingredient)
        return purchase
    }

    @Test func dates_PurchaseAfterCreation_IsBoughtWithThatDate() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchaseDate = try day(2)
        let purchase = makePurchase(of: ingredient, on: purchaseDate)

        let result = ShoppingListBought.dates(items: [item], purchases: [purchase], calendar: calendar)

        #expect(result[item.persistentModelID] == purchaseDate)
    }

    @Test func dates_PurchaseBeforeCreation_IsNotBought() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: ingredient, on: try day(-2))

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase], calendar: calendar).isEmpty)
    }

    @Test func dates_PurchaseAtMidnightOfCreationDay_IsBought() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let midnight = startOfCreationDay()
        let purchase = makePurchase(of: ingredient, on: midnight)

        let result = ShoppingListBought.dates(items: [item], purchases: [purchase], calendar: calendar)

        #expect(result[item.persistentModelID] == midnight)
    }

    @Test func dates_PurchaseEarlierSameDay_IsBought() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let earlier = try #require(calendar.date(byAdding: .hour, value: 3, to: startOfCreationDay()))
        #expect(earlier < created)
        let purchase = makePurchase(of: ingredient, on: earlier)

        let result = ShoppingListBought.dates(items: [item], purchases: [purchase], calendar: calendar)

        #expect(result[item.persistentModelID] == earlier)
    }

    @Test func dates_PurchaseAtCreationInstant_IsBought() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: ingredient, on: created)

        let result = ShoppingListBought.dates(items: [item], purchases: [purchase], calendar: calendar)

        #expect(result[item.persistentModelID] == created)
    }

    @Test func dates_PurchaseLastMomentOfPreviousDay_IsNotBought() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let justBefore = try #require(calendar.date(byAdding: .second, value: -1, to: startOfCreationDay()))
        let purchase = makePurchase(of: ingredient, on: justBefore)

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase], calendar: calendar).isEmpty)
    }

    @Test func dates_UnlinkedItem_IsNeverBought() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: nil)
        let purchase = makePurchase(of: ingredient, on: try day(2))

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase], calendar: calendar).isEmpty)
    }

    @Test func dates_SeveralQualifyingPurchases_PicksTheEarliest() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchases = [
            makePurchase(of: ingredient, on: try day(5)),
            makePurchase(of: ingredient, on: try day(-3)),
            makePurchase(of: ingredient, on: try day(1)),
            makePurchase(of: ingredient, on: try day(9))
        ]

        let result = ShoppingListBought.dates(items: [item], purchases: purchases, calendar: calendar)

        #expect(result[item.persistentModelID] == (try day(1)))
    }

    @Test func dates_PurchasesOfOtherIngredients_AreIgnored() throws {
        let ingredient = makeIngredient()
        let other = makeIngredient("Shea Butter")
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: other, on: try day(2))

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase], calendar: calendar).isEmpty)
    }

    @Test func dates_NoPurchasesOrItems_ReturnsEmpty() {
        let item = makeItem(ingredient: makeIngredient())

        #expect(ShoppingListBought.dates(items: [item], purchases: [], calendar: calendar).isEmpty)
        #expect(ShoppingListBought.dates(items: [], purchases: [], calendar: calendar).isEmpty)
    }

    @Test func dates_EachItemUsesItsOwnCreationDate() throws {
        let ingredient = makeIngredient()
        let early = makeItem("Early", ingredient: ingredient)
        let late = makeItem("Late", ingredient: ingredient)
        late.createdAt = try day(4)
        let purchase = makePurchase(of: ingredient, on: try day(2))

        let result = ShoppingListBought.dates(items: [early, late], purchases: [purchase], calendar: calendar)

        #expect(result[early.persistentModelID] != nil)
        #expect(result[late.persistentModelID] == nil)
    }
}
