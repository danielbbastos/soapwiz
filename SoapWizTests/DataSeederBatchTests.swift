import Testing
import Foundation
import SwiftData
import CloudKit
@testable import SoapWiz

/// The debug batches (SW-193). Making a batch draws stock, so they may only
/// land in a store this launch has just filled with test stock and recipes —
/// never one holding real purchases or recipes — and never one syncing to an
/// iCloud account, where each reinstall would add three more that can't be
/// deleted.
@Suite("DataSeeder – batches", .serialized)
@MainActor
struct DataSeederBatchTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    /// The two steps of a debug launch: the seeding in `SoapWizApp.init`, then
    /// the batches from its launch task.
    private func launch(
        _ ctx: ModelContext,
        storeIsMirrored: Bool = false,
        account: CKAccountStatus = .noAccount
    ) async {
        DataSeeder.seed(into: ctx)
        await DataSeeder.seedTestBatchesIfDue(
            into: ctx,
            storeIsMirrored: storeIsMirrored,
            account: StubSeederAccount(status: account)
        )
    }

    private func freshContext() throws -> (ModelContainer, ModelContext) {
        let (container, ctx) = try makeContext()
        try IngredientLibraryInstaller.installMissing(from: .bundled, in: ctx)
        return (container, ctx)
    }

    @Test func launch_FreshLocalStore_MakesOneBatchAtEachStageOfACure() async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx)

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

    /// A simulator with no account mirrors in name only: nothing uploads.
    @Test func launch_FreshMirroredStoreWithoutAnAccount_MakesBatches() async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx, storeIsMirrored: true, account: .noAccount)

        #expect(try ctx.fetchCount(FetchDescriptor<Batch>()) == 3)
    }

    /// Signed in, or not known to be signed out: the store may sync, so no
    /// batches.
    @Test(arguments: [CKAccountStatus.available, .couldNotDetermine, .temporarilyUnavailable, .restricted])
    func launch_FreshMirroredStoreThatMaySync_MakesNoBatches(_ status: CKAccountStatus) async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx, storeIsMirrored: true, account: status)

        #expect(try ctx.fetchCount(FetchDescriptor<Batch>()) == 0)
    }

    /// Real stock but no recipes yet: the recipes are seeded, but no batch
    /// draws from purchases that were already there.
    @Test func launch_StoreWithPurchasesButNoRecipes_MakesNoBatches() async throws {
        let (container, ctx) = try freshContext()
        _ = container
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

        await launch(ctx)

        #expect(try ctx.fetchCount(FetchDescriptor<Batch>()) == 0)
        #expect(purchase.remainingAmount == 5000)
    }

    @Test func launch_StoreWithRecipes_MakesNoBatches() async throws {
        let (container, ctx) = try freshContext()
        _ = container
        ctx.insert(Recipe(name: "My Own Bar"))
        try ctx.save()

        await launch(ctx)

        #expect(try ctx.fetchCount(FetchDescriptor<Batch>()) == 0)
    }

    /// Once per launch: a second window's launch task finds nothing due.
    @Test func seedTestBatchesIfDue_CalledTwice_SeedsOnce() async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx)
        await DataSeeder.seedTestBatchesIfDue(into: ctx, storeIsMirrored: false, account: StubSeederAccount(status: .noAccount))

        #expect(try ctx.fetchCount(FetchDescriptor<Batch>()) == 3)
    }
}

private nonisolated struct StubSeederAccount: SyncAccountStatusProviding {
    let status: CKAccountStatus

    func accountStatus() async -> CKAccountStatus { status }
}
