import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Last purchase")
@MainActor
struct LastPurchaseTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
    }

    @discardableResult
    private func addPurchase(
        to ingredient: Ingredient,
        quantity: Double = 100,
        totalPrice: Double = 10,
        daysAgo: Int = 1,
        provider: Provider? = nil
    ) throws -> IngredientPurchase {
        let date = try #require(Calendar.current.date(byAdding: .day, value: -daysAgo, to: now))
        let purchase = IngredientPurchase(
            provider: provider,
            dateOfPurchase: date,
            quantity: quantity,
            totalPrice: totalPrice,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        context.insert(purchase)
        purchase.attach(to: ingredient)
        return purchase
    }

    private func makeIngredient(_ name: String = "Olive Oil") -> Ingredient {
        let ingredient = Ingredient(name: name, unit: "g")
        context.insert(ingredient)
        return ingredient
    }

    @Test func newest_PicksTheLatestPurchasePerIngredient() throws {
        let ingredient = makeIngredient()
        let other = makeIngredient("Shea Butter")
        let older = Provider(name: "Old Shop")
        let newer = Provider(name: "New Shop")
        context.insert(older)
        context.insert(newer)
        let oldPurchase = try addPurchase(to: ingredient, quantity: 100, totalPrice: 5, daysAgo: 30, provider: older)
        let newPurchase = try addPurchase(to: ingredient, quantity: 200, totalPrice: 20, daysAgo: 3, provider: newer)
        let otherPurchase = try addPurchase(to: other, quantity: 50, totalPrice: 5, daysAgo: 9)

        let result = LastPurchase.newest(in: [oldPurchase, newPurchase, otherPurchase])

        let last = try #require(result[ingredient.persistentModelID])
        #expect(last.quantity == 200)
        #expect(last.supplierName == "New Shop")
        #expect(last.pricePerUnit == 0.1)
        #expect(result[other.persistentModelID]?.quantity == 50)
        #expect(result.count == 2)
    }

    @Test func newest_PurchaseWithoutIngredient_IsIgnored() {
        let purchase = IngredientPurchase(
            provider: nil,
            dateOfPurchase: now,
            quantity: 100,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        context.insert(purchase)

        #expect(LastPurchase.newest(in: [purchase]).isEmpty)
    }

    @Test func newest_NoPurchases_IsEmpty() {
        #expect(LastPurchase.newest(in: []).isEmpty)
    }

    @Test func init_ZeroQuantity_HasNoQuantity() throws {
        let purchase = try addPurchase(to: makeIngredient(), quantity: 0, totalPrice: 10)

        #expect(LastPurchase(purchase).quantity == nil)
    }

    @Test func init_NoProvider_HasNoSupplier() throws {
        let purchase = try addPurchase(to: makeIngredient())

        #expect(LastPurchase(purchase).supplierName == nil)
    }

    @Test func init_EmptyProviderName_HasNoSupplier() throws {
        let provider = Provider(name: "")
        context.insert(provider)
        let purchase = try addPurchase(to: makeIngredient(), provider: provider)

        #expect(LastPurchase(purchase).supplierName == nil)
    }

    @Test func init_FreePurchase_HasNoPrice() throws {
        let purchase = try addPurchase(to: makeIngredient(), totalPrice: 0)

        #expect(LastPurchase(purchase).pricePerUnit == nil)
    }

    @Test func line_NothingKnown_IsNil() {
        let last = LastPurchase(quantity: nil, supplierName: nil, pricePerUnit: nil)

        #expect(last.line(unit: "g", currencyCode: "EUR") == nil)
    }

    @Test func line_QuantityOnly_LeadsWithLastPurchase() throws {
        let last = LastPurchase(quantity: 500, supplierName: nil, pricePerUnit: nil)

        let line = try #require(last.line(unit: "g", currencyCode: "EUR"))
        #expect(line.hasPrefix("Last purchase: "))
        #expect(line.hasSuffix(" g"))
        #expect(!line.contains("·"))
    }

    @Test func line_NonDefaultLocale_FormatsQuantityWithThatLocale() throws {
        let german = Locale(identifier: "de_DE")
        let last = LastPurchase(quantity: 1.5, supplierName: nil, pricePerUnit: 0.1)
        let number = 1.5.formatted(.number.precision(.fractionLength(0...2)).locale(german))
        let price = 0.1.unitPriceFormatted(currencyCode: "EUR", locale: german)

        let line = try #require(last.line(unit: "g", currencyCode: "EUR", locale: german))

        #expect(number != "1.5")
        #expect(line.contains("\(number) g"))
        #expect(line.contains(price))
    }

    @Test func line_NoQuantity_ShowsSupplierAndPriceAlone() throws {
        let last = LastPurchase(quantity: nil, supplierName: "Shop", pricePerUnit: 0.1)

        let line = try #require(last.line(unit: "g", currencyCode: "EUR"))
        #expect(line.hasPrefix("Shop · "))
        #expect(!line.contains("Last purchase"))
    }

    @Test func line_Everything_JoinsPartsWithDots() throws {
        let last = LastPurchase(quantity: 500, supplierName: "Shop", pricePerUnit: 0.1)

        let line = try #require(last.line(unit: "g", currencyCode: "EUR"))
        #expect(line.components(separatedBy: " · ").count == 3)
        #expect(line.contains("Shop"))
    }
}
