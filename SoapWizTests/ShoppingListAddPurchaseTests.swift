import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Shopping list add purchase")
@MainActor
struct ShoppingListAddPurchaseTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let now: Date
    private let sut: ShoppingListViewModel
    private let locale = Locale(identifier: "en_US_POSIX")

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
        let fixedNow = try #require(
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))
        )
        now = fixedNow
        sut = ShoppingListViewModel(modelContext: context, now: { fixedNow })
    }

    private func makeIngredient(unit: String = "g") -> Ingredient {
        let ingredient = Ingredient(name: "Olive Oil", unit: unit)
        context.insert(ingredient)
        return ingredient
    }

    @discardableResult
    private func addPurchase(to ingredient: Ingredient, provider: Provider?, daysAgo: Double) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            provider: provider,
            dateOfPurchase: now.addingTimeInterval(-daysAgo * 86_400),
            quantity: 100,
            totalPrice: 5,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        context.insert(purchase)
        purchase.attach(to: ingredient)
        return purchase
    }

    private func makeItem(ingredient: Ingredient?, amount: Double?, unit: String = "g") -> ShoppingListItem {
        let item = ShoppingListItem(name: "Olive Oil", amount: amount, unit: unit, ingredient: ingredient)
        context.insert(item)
        return item
    }

    private func fieldText(_ value: Double) -> String {
        value.formatted(
            FloatingPointFormatStyle<Double>(locale: locale)
                .precision(.fractionLength(0...2))
                .grouping(.never)
        )
    }

    @Test func purchasePrefill_TwoPurchases_UsesNewestProvider() throws {
        let ingredient = makeIngredient()
        let older = Provider(name: "Older")
        let newer = Provider(name: "Newer")
        context.insert(older)
        context.insert(newer)
        let oldPurchase = addPurchase(to: ingredient, provider: older, daysAgo: 30)
        let newPurchase = addPurchase(to: ingredient, provider: newer, daysAgo: 2)
        let item = makeItem(ingredient: ingredient, amount: 500)

        let prefill = try #require(sut.purchasePrefill(for: item, purchases: [oldPurchase, newPurchase]))

        #expect(prefill.provider === newer)
    }

    @Test func purchasePrefill_MatchingUnits_FillsQuantity() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient, amount: 500)

        let prefill = try #require(sut.purchasePrefill(for: item, purchases: []))

        #expect(prefill.quantity == 500)
    }

    @Test func purchasePrefill_DifferentUnits_LeavesQuantityNil() throws {
        let ingredient = makeIngredient(unit: "g")
        let item = makeItem(ingredient: ingredient, amount: 2, unit: "kg")

        let prefill = try #require(sut.purchasePrefill(for: item, purchases: []))

        #expect(prefill.quantity == nil)
    }

    @Test func purchasePrefill_NoAmount_LeavesQuantityNil() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient, amount: nil)

        let prefill = try #require(sut.purchasePrefill(for: item, purchases: []))

        #expect(prefill.quantity == nil)
    }

    @Test func purchasePrefill_ZeroAmount_LeavesQuantityNil() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient, amount: 0)

        let prefill = try #require(sut.purchasePrefill(for: item, purchases: []))

        #expect(prefill.quantity == nil)
    }

    @Test func purchasePrefill_NeverBought_LeavesProviderNil() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient, amount: 500)

        let prefill = try #require(sut.purchasePrefill(for: item, purchases: []))

        #expect(prefill.provider == nil)
    }

    @Test func purchasePrefill_OtherIngredientPurchase_IsIgnored() throws {
        let ingredient = makeIngredient()
        let other = Ingredient(name: "Shea", unit: "g")
        context.insert(other)
        let provider = Provider(name: "Elsewhere")
        context.insert(provider)
        let purchase = addPurchase(to: other, provider: provider, daysAgo: 1)
        let item = makeItem(ingredient: ingredient, amount: 500)

        let prefill = try #require(sut.purchasePrefill(for: item, purchases: [purchase]))

        #expect(prefill.provider == nil)
    }

    @Test func purchasePrefill_UnlinkedItem_ReturnsNil() {
        let item = makeItem(ingredient: nil, amount: 500)

        #expect(sut.purchasePrefill(for: item, purchases: []) == nil)
    }

    @Test func offersAddPurchase_CheckedLinkedNotBought_IsTrue() {
        let item = makeItem(ingredient: makeIngredient(), amount: 1)
        item.isChecked = true

        #expect(sut.offersAddPurchase(item, boughtDate: nil))
    }

    @Test func offersAddPurchase_NotChecked_IsFalse() {
        let item = makeItem(ingredient: makeIngredient(), amount: 1)

        #expect(!sut.offersAddPurchase(item, boughtDate: nil))
    }

    @Test func offersAddPurchase_AlreadyBought_IsFalse() {
        let item = makeItem(ingredient: makeIngredient(), amount: 1)
        item.isChecked = true

        #expect(!sut.offersAddPurchase(item, boughtDate: now))
    }

    @Test func offersAddPurchase_Unlinked_IsFalse() {
        let item = makeItem(ingredient: nil, amount: 1)
        item.isChecked = true

        #expect(!sut.offersAddPurchase(item, boughtDate: nil))
    }

    @Test func form_Prefill_SetsProviderAndQuantity() throws {
        let ingredient = makeIngredient()
        let provider = Provider(name: "Shop")
        context.insert(provider)

        let form = PurchaseFormViewModel(
            ingredient: ingredient,
            prefill: PurchasePrefill(provider: provider, quantity: 1250.5),
            locale: locale
        )

        #expect(form.selectedProvider === provider)
        #expect(form.quantityText == fieldText(1250.5))
        #expect(form.quantity == 1250.5)
    }

    @Test func form_UntouchedPrefill_IsNotDirty() {
        let ingredient = makeIngredient()
        let provider = Provider(name: "Shop")
        context.insert(provider)

        let form = PurchaseFormViewModel(
            ingredient: ingredient,
            prefill: PurchasePrefill(provider: provider, quantity: 500),
            locale: locale
        )

        #expect(!form.isDirty)
    }

    @Test func form_UntouchedPrefill_IsValid() {
        let ingredient = makeIngredient()
        let form = PurchaseFormViewModel(
            ingredient: ingredient,
            prefill: PurchasePrefill(provider: nil, quantity: 500),
            locale: locale
        )

        #expect(form.isValid)
        #expect(!form.isDirty)
    }

    @Test func form_BlankNewPurchase_IsInvalid() {
        let form = PurchaseFormViewModel(ingredient: makeIngredient(), locale: locale)

        #expect(!form.isValid)
    }

    @Test func form_EditingUnchangedPurchase_IsInvalid() {
        let ingredient = makeIngredient()
        let existing = addPurchase(to: ingredient, provider: nil, daysAgo: 1)
        let form = PurchaseFormViewModel(ingredient: ingredient, purchase: existing, locale: locale)

        #expect(!form.isValid)
    }

    @Test func form_EditedPrefill_IsDirty() {
        let ingredient = makeIngredient()
        let form = PurchaseFormViewModel(
            ingredient: ingredient,
            prefill: PurchasePrefill(provider: nil, quantity: 500),
            locale: locale
        )

        form.totalPriceText = "12"

        #expect(form.isDirty)
    }

    @Test func form_PrefillWhileEditing_IsIgnored() {
        let ingredient = makeIngredient()
        let existing = addPurchase(to: ingredient, provider: nil, daysAgo: 1)
        let provider = Provider(name: "Shop")
        context.insert(provider)

        let form = PurchaseFormViewModel(
            ingredient: ingredient,
            purchase: existing,
            prefill: PurchasePrefill(provider: provider, quantity: 999),
            locale: locale
        )

        #expect(form.selectedProvider == nil)
        #expect(form.quantityText == fieldText(100))
    }

    @Test func form_WithoutPrefill_StartsEmpty() {
        let form = PurchaseFormViewModel(ingredient: makeIngredient(), locale: locale)

        #expect(form.selectedProvider == nil)
        #expect(form.quantityText.isEmpty)
        #expect(!form.isDirty)
    }
}
