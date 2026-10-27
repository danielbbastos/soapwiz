import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("InventoryImportApplier", .serialized)
@MainActor
struct InventoryImportApplierTests {

    private typealias Support = InventoryImportTestSupport

    private func apply(
        _ rows: [InventoryImportRow],
        in context: ModelContext,
        edit: (inout InventoryImportPlan) -> Void = { _ in }
    ) throws -> InventoryImportResult {
        let inventory = try context.fetch(FetchDescriptor<Ingredient>())
        var plan = Support.plan(rows, inventory: inventory)
        edit(&plan)
        return try InventoryImportApplier.apply(plan, in: context)
    }

    private func ingredient(named name: String, in context: ModelContext) throws -> Ingredient {
        try #require(try context.fetch(FetchDescriptor<Ingredient>()).first { $0.name == name })
    }

    // MARK: - Ingredients and purchases

    @Test func apply_NewIngredient_IsCreatedWithItsPurchases() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let expiry = Calendar.current.date(byAdding: .month, value: 6, to: date)

        let result = try apply([
            InventoryImportRow(name: "Zzyzx Butter", unit: .kilograms, quantity: 2, totalPrice: 12, purchaseDate: date, expiryDate: expiry),
            InventoryImportRow(name: "zzyzx butter", unit: .grams, quantity: 500, totalPrice: 3)
        ], in: context)

        let created = try ingredient(named: "Zzyzx Butter", in: context)
        let purchases = created.purchases.sorted { $0.totalPrice > $1.totalPrice }
        #expect(created.unit == "kg")
        #expect(purchases.count == 2)
        #expect(purchases[0].quantity == 2)
        #expect(purchases[0].remainingAmount == 2)
        #expect(purchases[0].totalPrice == 12)
        #expect(purchases[0].dateOfPurchase == date)
        #expect(purchases[0].expiryDate == expiry)
        #expect(purchases[0].badge.isEmpty)
        #expect(purchases[0].openingDate == nil)
        #expect(purchases[1].quantity == 0.5)
        #expect(result == InventoryImportResult(importedRows: 2, skippedRows: 0, ingredientsCreated: 1, purchasesAdded: 2))
    }

    @Test func apply_RowWithoutPriceOrDate_DefaultsToZeroAndNow() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let before = Date.now

        _ = try apply([InventoryImportRow(name: "Zzyzx Butter", quantity: 5)], in: context)

        let purchase = try #require(try ingredient(named: "Zzyzx Butter", in: context).purchases.first)
        #expect(purchase.totalPrice == 0)
        #expect(purchase.dateOfPurchase >= before)
        #expect(purchase.provider == nil)
        #expect(purchase.ingredientSlug.isEmpty)
    }

    @Test func apply_NoQuantityRow_CreatesTheIngredientOnly() throws {
        let (container, context) = try Support.makeContext()
        _ = container

        let result = try apply([InventoryImportRow(name: "Zzyzx Butter")], in: context)

        #expect(try ingredient(named: "Zzyzx Butter", in: context).purchases.isEmpty)
        #expect(result == InventoryImportResult(importedRows: 1, skippedRows: 0, ingredientsCreated: 1, purchasesAdded: 0))
    }

    @Test func apply_MatchedIngredient_OnlyGainsAPurchase() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient(
            "Olive Oil", unit: .grams, density: 0.9, slug: "olive-oil", code: "OLO", isHidden: true, in: context
        )
        olive.sapValue = 0.135
        try context.save()

        let result = try apply([
            InventoryImportRow(name: "olive oil", categoryName: "Other", unit: .kilograms, quantity: 1, totalPrice: 9)
        ], in: context)

        #expect(olive.name == "Olive Oil")
        #expect(olive.unit == "g")
        #expect(olive.density == 0.9)
        #expect(olive.sapValue == 0.135)
        #expect(olive.code == "OLO")
        #expect(olive.isHidden)
        #expect(olive.category == nil)
        let purchase = try #require(olive.purchases.first)
        #expect(olive.purchases.count == 1)
        #expect(purchase.quantity == 1000)
        #expect(purchase.ingredientSlug == "olive-oil")
        #expect(result == InventoryImportResult(importedRows: 1, skippedRows: 0, ingredientsCreated: 0, purchasesAdded: 1))
        #expect(try context.fetch(FetchDescriptor<IngredientCategory>()).isEmpty)
    }

    @Test func apply_NewIngredientFromLibraryName_AdoptsTheEntry() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let entry = try #require(IngredientLibrary.entry(matching: "Olive Oil"))

        _ = try apply([InventoryImportRow(name: "My Olive", quantity: 1), InventoryImportRow(name: "olive oil", quantity: 2)], in: context)

        let ingredients = try context.fetch(FetchDescriptor<Ingredient>())
        let created = try #require(ingredients.first { $0.librarySlug == entry.slug })
        #expect(ingredients.count == 2)
        #expect(created.sapValue == entry.sapValue)
        #expect(created.density == entry.density)
        #expect(created.fattyAcidProfile == entry.fattyAcidProfile)
        #expect(created.code == entry.code)
        #expect(created.category?.name == entry.category)
    }

    @Test func apply_LibraryAdoptedPurchases_CarryTheSlug() throws {
        let (container, context) = try Support.makeContext()
        _ = container

        _ = try apply([InventoryImportRow(name: "Olive Oil", quantity: 1)], in: context)

        let purchase = try #require(try context.fetch(FetchDescriptor<IngredientPurchase>()).first)
        #expect(purchase.ingredientSlug == "olive-oil")
    }

    // MARK: - Categories

    @Test func apply_ExistingCategory_IsReusedByLookupKey() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let oils = IngredientCategory(name: "Oils")
        context.insert(oils)

        _ = try apply([
            InventoryImportRow(name: "Zzyzx Butter", categoryName: "  OILS ", quantity: 1),
            InventoryImportRow(name: "Qqq Wax", categoryName: "oils", quantity: 1)
        ], in: context)

        #expect(try ingredient(named: "Zzyzx Butter", in: context).category === oils)
        #expect(try ingredient(named: "Qqq Wax", in: context).category === oils)
        #expect(try context.fetch(FetchDescriptor<IngredientCategory>()).count == 1)
    }

    @Test func apply_UnknownCategory_IsCreatedOnceForSeveralIngredients() throws {
        let (container, context) = try Support.makeContext()
        _ = container

        _ = try apply([
            InventoryImportRow(name: "Zzyzx Butter", categoryName: "Exotics", quantity: 1),
            InventoryImportRow(name: "Qqq Wax", categoryName: "exotics", quantity: 1)
        ], in: context)

        let categories = try context.fetch(FetchDescriptor<IngredientCategory>())
        #expect(categories.map(\.name) == ["Exotics"])
        #expect(try ingredient(named: "Qqq Wax", in: context).category === categories.first)
    }

    @Test func apply_NoCategory_FallsBackToOthers() throws {
        let (container, context) = try Support.makeContext()
        _ = container

        _ = try apply([InventoryImportRow(name: "Zzyzx Butter", quantity: 1)], in: context)

        #expect(try ingredient(named: "Zzyzx Butter", in: context).category?.name == IngredientCategory.Name.others)
    }

    @Test func apply_EditedCategory_IsUsed() throws {
        let (container, context) = try Support.makeContext()
        _ = container

        _ = try apply([InventoryImportRow(name: "Zzyzx Butter", quantity: 1)], in: context) { plan in
            plan.setCategory("Butters", forEntry: plan.entries[0].id)
        }

        #expect(try ingredient(named: "Zzyzx Butter", in: context).category?.name == "Butters")
    }

    // MARK: - Providers

    @Test func apply_Supplier_IsReusedOrCreatedByLookupKey() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let existing = Provider(name: "Acme Soap Supply")
        context.insert(existing)

        _ = try apply([
            InventoryImportRow(name: "Zzyzx Butter", quantity: 1, supplier: " acme soap supply "),
            InventoryImportRow(name: "Zzyzx Butter", quantity: 1, supplier: "Bée Supply"),
            InventoryImportRow(name: "Zzyzx Butter", quantity: 1, supplier: "BEE SUPPLY"),
            InventoryImportRow(name: "Zzyzx Butter", quantity: 1, supplier: "  ")
        ], in: context)

        let providers = try context.fetch(FetchDescriptor<Provider>())
        let purchases = try ingredient(named: "Zzyzx Butter", in: context).purchases
        #expect(providers.count == 2)
        #expect(purchases.filter { $0.provider === existing }.count == 1)
        #expect(purchases.filter { $0.provider == nil }.count == 1)
    }

    // MARK: - Codes

    @Test func apply_NewIngredientCodes_AreUniqueWithinThePassAndStore() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        Support.insertIngredient("Existing", code: "ZBU", in: context)

        _ = try apply([
            InventoryImportRow(name: "Zzyzx Butter", quantity: 1),
            InventoryImportRow(name: "Zebu Butter", quantity: 1),
            InventoryImportRow(name: "Zulu Butter", quantity: 1)
        ], in: context)

        let codes = try context.fetch(FetchDescriptor<Ingredient>()).map(\.code).filter { !$0.isEmpty }.map { $0.uppercased() }
        #expect(Set(codes).count == codes.count)
        #expect(codes.count == 4)
    }

    @Test func apply_JournalCodes_ContinueTheIngredientsSequence() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("My Oil", code: "MYO", in: context)
        let prior = IngredientPurchase(
            dateOfPurchase: .now, quantity: 1, totalPrice: 1, badge: "", journalCode: "MYO-004", expiryDate: nil, openingDate: nil
        )
        context.insert(prior)
        prior.attach(to: olive)

        _ = try apply([
            InventoryImportRow(name: "My Oil", quantity: 1),
            InventoryImportRow(name: "My Oil", quantity: 2)
        ], in: context)

        let codes = olive.purchases.map(\.journalCode).sorted()
        #expect(codes == ["MYO-004", "MYO-005", "MYO-006"])
    }

    @Test func apply_NewIngredient_JournalCodesStartAtOne() throws {
        let (container, context) = try Support.makeContext()
        _ = container

        _ = try apply([
            InventoryImportRow(name: "Zzyzx Butter", quantity: 1),
            InventoryImportRow(name: "Zzyzx Butter", quantity: 1)
        ], in: context)

        let created = try ingredient(named: "Zzyzx Butter", in: context)
        let prefix = created.code + "-"
        #expect(created.purchases.map(\.journalCode).sorted() == [prefix + "001", prefix + "002"])
    }

    // MARK: - Inclusion and failure

    @Test func apply_OnlyIncludedRows_AreWritten() throws {
        let (container, context) = try Support.makeContext()
        _ = container

        let result = try apply([
            InventoryImportRow(name: "Zzyzx Butter", quantity: 1),
            InventoryImportRow(name: "Qqq Wax", quantity: 1),
            InventoryImportRow(name: "Bad Wax", quantity: -1),
            InventoryImportRow(name: "", quantity: 1)
        ], in: context) { plan in
            plan.setIncluded(false, forEntry: plan.entries[1].id)
        }

        let names = try context.fetch(FetchDescriptor<Ingredient>()).map(\.name)
        #expect(names == ["Zzyzx Butter"])
        #expect(result == InventoryImportResult(importedRows: 1, skippedRows: 3, ingredientsCreated: 1, purchasesAdded: 1))
    }

    @Test func apply_NothingIncluded_WritesNothing() throws {
        let (container, context) = try Support.makeContext()
        _ = container

        let result = try apply([InventoryImportRow(name: "Zzyzx Butter", quantity: 1)], in: context) { plan in
            plan.setIncluded(false, forEntry: plan.entries[0].id)
        }

        #expect(result == InventoryImportResult(importedRows: 0, skippedRows: 1, ingredientsCreated: 0, purchasesAdded: 0))
        #expect(try context.fetch(FetchDescriptor<Ingredient>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<IngredientCategory>()).isEmpty)
        #expect(!context.hasChanges)
    }

    @Test func apply_OnlyNoQuantityMatches_WritesNothingAndSkipsThem() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", in: context)
        try context.save()

        let result = try apply([InventoryImportRow(name: "Olive Oil"), InventoryImportRow(name: "Olive Oil", quantity: 0)], in: context)

        #expect(olive.purchases.isEmpty)
        #expect(try context.fetch(FetchDescriptor<IngredientPurchase>()).isEmpty)
        #expect(!context.hasChanges)
        #expect(result == InventoryImportResult(importedRows: 0, skippedRows: 2, ingredientsCreated: 0, purchasesAdded: 0))
    }

    @Test func apply_MatchMergedAwayBeforeApply_SkipsItsRowsAndKeepsTheRest() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let loser = Support.insertIngredient("Olive Oil", slug: "olive-oil", in: context)
        let survivor = Support.insertIngredient("Olive Oil", slug: "olive-oil", in: context)
        try context.save()
        let plan = Support.plan(
            [InventoryImportRow(name: "Olive Oil", quantity: 5), InventoryImportRow(name: "Zzyzx Butter", quantity: 1)],
            inventory: [loser]
        )
        context.delete(loser)
        try context.save()

        let result = try InventoryImportApplier.apply(plan, in: context)

        #expect(survivor.purchases.count == 1)
        #expect(result.importedRows == 2)
        #expect(result.purchasesAdded == 2)
    }

    @Test func apply_SurvivorWithAnotherUnit_ConvertsIntoTheSurvivorsUnit() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let loser = Support.insertIngredient("Olive Oil", unit: .grams, slug: "olive-oil", in: context)
        let survivor = Support.insertIngredient("Olive Oil", unit: .kilograms, slug: "olive-oil", in: context)
        try context.save()
        let plan = Support.plan([InventoryImportRow(name: "Olive Oil", unit: .grams, quantity: 500)], inventory: [loser])
        context.delete(loser)
        try context.save()

        let result = try InventoryImportApplier.apply(plan, in: context)

        let purchase = try #require(survivor.purchases.first)
        #expect(purchase.quantity == 0.5)
        #expect(result == InventoryImportResult(importedRows: 1, skippedRows: 0, ingredientsCreated: 0, purchasesAdded: 1))
    }

    @Test func apply_SurvivorThatCannotTakeTheRow_SkipsItAndWritesNothingForIt() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let loser = Support.insertIngredient("Olive Oil", unit: .grams, slug: "olive-oil", in: context)
        let survivor = Support.insertIngredient("Olive Oil", unit: .units, slug: "olive-oil", in: context)
        try context.save()
        let plan = Support.plan(
            [InventoryImportRow(name: "Olive Oil", unit: .grams, quantity: 500), InventoryImportRow(name: "Zzyzx Butter", quantity: 1)],
            inventory: [loser]
        )
        context.delete(loser)
        try context.save()

        let result = try InventoryImportApplier.apply(plan, in: context)

        #expect(survivor.purchases.isEmpty)
        #expect(try context.fetch(FetchDescriptor<IngredientPurchase>()).count == 1)
        #expect(result == InventoryImportResult(importedRows: 1, skippedRows: 1, ingredientsCreated: 1, purchasesAdded: 1))
    }
}
