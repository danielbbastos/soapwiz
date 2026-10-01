import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The debug batches (SW-193). Making a batch draws stock, so they may only
/// land in a store this launch has just filled with test stock and recipes —
/// never one holding real purchases or recipes.
@Suite("DataSeeder – batches", .serialized)
@MainActor
struct DataSeederBatchTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    @Test func seed_FreshStore_MakesOneBatchAtEachStageOfACure() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: .bundled, in: ctx)

        DataSeeder.seed(into: ctx)

        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        #expect(batches.count == 3)
        let woodland = try #require(batches.first { $0.recipeName == "Woodland Meadow Bar" })
        let castile = try #require(batches.first { $0.recipeName == "Pure Castile" })
        let kitchen = try #require(batches.first { $0.recipeName == "Everyday Kitchen Bar" })
        guard case .curing(_, let woodlandProgress) = woodland.cureStatus,
              case .curing(_, let castileProgress) = castile.cureStatus else {
            Issue.record("Expected Woodland and Castile to be curing")
            return
        }
        #expect((0.7...0.8).contains(woodlandProgress))
        #expect(castileProgress < 0.2)
        #expect(kitchen.cureStatus == .ready)
    }

    /// Real stock but no recipes yet: the recipes are seeded, but no batch
    /// draws from purchases that were already there.
    @Test func seed_StoreWithPurchasesButNoRecipes_MakesNoBatches() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: .bundled, in: ctx)
        let ingredient = try #require(try ctx.fetch(
            FetchDescriptor<Ingredient>(predicate: #Predicate { $0.librarySlug == "olive-oil" })
        ).first)
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: 5000,
            totalPrice: 50,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        ctx.insert(purchase)
        purchase.attach(to: ingredient)
        try ctx.save()

        DataSeeder.seed(into: ctx)

        #expect(try ctx.fetchCount(FetchDescriptor<Batch>()) == 0)
        #expect(purchase.remainingAmount == 5000)
    }

    @Test func seed_StoreWithRecipes_MakesNoBatches() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: .bundled, in: ctx)
        ctx.insert(Recipe(name: "My Own Bar"))
        try ctx.save()

        DataSeeder.seed(into: ctx)

        #expect(try ctx.fetchCount(FetchDescriptor<Batch>()) == 0)
    }
}
