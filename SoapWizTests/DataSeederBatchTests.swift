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

    /// The seeding a debug launch does from `SoapWizApp`'s launch task.
    private func launch(
        _ ctx: ModelContext,
        store: ModelContainerFactory.ActiveStore = .mirrored,
        account: CKAccountStatus = .noAccount
    ) async {
        await DataSeeder.seedTestDataIfDue(
            into: ctx,
            activeStore: store,
            account: StubSeederAccount(status: account)
        )
    }

    private func counts(_ ctx: ModelContext) throws -> SeededCounts {
        SeededCounts(
            purchases: try ctx.fetchCount(FetchDescriptor<IngredientPurchase>()),
            recipes: try ctx.fetchCount(FetchDescriptor<Recipe>()),
            batches: try ctx.fetchCount(FetchDescriptor<Batch>())
        )
    }

    private func freshContext() throws -> (ModelContainer, ModelContext) {
        let (container, ctx) = try makeContext()
        try IngredientLibraryInstaller.installMissing(from: .bundled, in: ctx)
        return (container, ctx)
    }

    @Test func launch_FreshStoreWithoutAnAccount_MakesOneBatchAtEachStageOfACure() async throws {
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

    /// With no account there's nothing to upload to — until the simulator is
    /// signed in, which is a deliberate step and accepted.
    @Test(arguments: [
        ModelContainerFactory.ActiveStore.mirrored,
        .localFallback(reason: "Schema not deployed")
    ])
    func launch_FreshStoreThatMayMirrorWithoutAnAccount_MakesBatches(
        _ store: ModelContainerFactory.ActiveStore
    ) async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx, store: store, account: .noAccount)

        #expect(try ctx.fetchCount(FetchDescriptor<Batch>()) == 3)
    }

    /// A local-only build opens the file an entitled build installed over it
    /// would mirror, and can't ask about the account — so never, whatever the
    /// account. "No account" is in the list because it would let any other
    /// store through.
    @Test(arguments: [CKAccountStatus.noAccount, .available])
    func launch_FreshLocalOnlyStore_MakesNoBatches(_ status: CKAccountStatus) async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx, store: .notMirrored, account: status)

        #expect(try ctx.fetchCount(FetchDescriptor<Batch>()) == 0)
    }

    /// A store the user took offline mirrors again once sync is back on, and
    /// with no account check to go on, it gets none.
    @Test(arguments: [CKAccountStatus.noAccount, .available])
    func launch_FreshStoreWithSyncTurnedOff_MakesNoBatches(_ status: CKAccountStatus) async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx, store: .offlineByChoice, account: status)

        #expect(try ctx.fetchCount(FetchDescriptor<Batch>()) == 0)
    }

    /// A free user's store is the file that mirrors once they buy Pro, so it
    /// is held to the same rule as a store with sync turned off.
    @Test(arguments: [CKAccountStatus.noAccount, .available])
    func launch_FreshStoreThatRequiresPro_MakesNoBatches(_ status: CKAccountStatus) async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx, store: .requiresPro, account: status)

        #expect(try ctx.fetchCount(FetchDescriptor<Batch>()) == 0)
    }

    /// Signed in, or not known to be signed out: the store may sync, so no
    /// batches.
    @Test(arguments: [CKAccountStatus.available, .couldNotDetermine, .temporarilyUnavailable, .restricted])
    func launch_FreshMirroredStoreThatMaySync_MakesNoBatches(_ status: CKAccountStatus) async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx, store: .mirrored, account: status)

        #expect(try ctx.fetchCount(FetchDescriptor<Batch>()) == 0)
    }

    /// A local fallback is the same file the next launch may mirror, so a
    /// signed-in account blocks the batches there too.
    @Test func launch_FreshLocalFallbackWithAnAccount_MakesNoBatches() async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx, store: .localFallback(reason: "Schema not deployed"), account: .available)

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

    /// A second launch task (another window) finds the stock and recipes
    /// already there, so it adds nothing, batches included.
    @Test func seedTestDataIfDue_CalledTwiceOnSameStore_SeedsOnce() async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx)
        let first = try counts(ctx)
        await launch(ctx)
        let second = try counts(ctx)

        #expect(first.batches == 3)
        #expect(first.purchases > 0)
        #expect(first.recipes == 5)
        #expect(second == first)
    }

    /// The Mac case: a free user's store is local, and the account is signed in.
    /// Nothing of the test data may reach it.
    @Test(arguments: [
        ModelContainerFactory.ActiveStore.requiresPro,
        .mirrored,
        .localFallback(reason: "Schema not deployed"),
        .notMirrored,
        .offlineByChoice
    ])
    func launch_SignedInAccount_SeedsNothing(_ store: ModelContainerFactory.ActiveStore) async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx, store: store, account: .available)

        #expect(try counts(ctx) == .none)
    }

    @Test(arguments: [CKAccountStatus.couldNotDetermine, .restricted, .temporarilyUnavailable])
    func launch_AccountNotKnownToBeAbsent_SeedsNothing(_ status: CKAccountStatus) async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx, store: .mirrored, account: status)

        #expect(try counts(ctx) == .none)
    }

    @Test func launch_NoAccountOnLocalStoreThatRequiresPro_SeedsStockAndRecipesButNoBatches() async throws {
        let (container, ctx) = try freshContext()
        _ = container

        await launch(ctx, store: .requiresPro, account: .noAccount)

        let seeded = try counts(ctx)
        #expect(seeded.purchases > 0)
        #expect(seeded.recipes == 5)
        #expect(seeded.batches == 0)
    }

    /// Inventory refetches on a save, so what was seeded must be saved.
    @Test(arguments: [
        ModelContainerFactory.ActiveStore.mirrored,
        .requiresPro
    ])
    func launch_NoAccount_SavesWhatItSeeded(_ store: ModelContainerFactory.ActiveStore) async throws {
        let (container, ctx) = try freshContext()
        _ = container
        ctx.autosaveEnabled = false
        try ctx.save()
        #expect(!ctx.hasChanges)

        await launch(ctx, store: store, account: .noAccount)

        #expect(try counts(ctx).purchases > 0)
        #expect(!ctx.hasChanges)
    }

    @Test func launch_NoAccountStoreWithPurchaseAndRecipe_AddsNothing() async throws {
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
        ctx.insert(Recipe(name: "My Own Bar"))
        try ctx.save()

        await launch(ctx, store: .mirrored, account: .noAccount)

        let seeded = try counts(ctx)
        #expect(seeded.purchases == 1)
        #expect(seeded.recipes == 1)
        #expect(seeded.batches == 0)
    }
}

private struct SeededCounts: Equatable {
    static let none = SeededCounts(purchases: 0, recipes: 0, batches: 0)

    let purchases: Int
    let recipes: Int
    let batches: Int
}

private nonisolated struct StubSeederAccount: SyncAccountStatusProviding {
    let status: CKAccountStatus

    func accountStatus() async -> CKAccountStatus { status }
}
