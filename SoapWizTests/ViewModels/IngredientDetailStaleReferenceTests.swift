import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The ingredient detail screen reads every field it draws off one captured
/// `Ingredient`. When the duplicate merge deletes that row the reference is
/// detached, and reading a to-many off a detached model yields **nothing** rather
/// than trapping — so the screen silently empties: no purchases, no stock, no
/// usage, including the purchases that did sync.
///
/// Observed on device during SW-136 testing: a purchase added from that screen
/// was written correctly (`LiveIngredient` routed it to the survivor) but the
/// screen behind it showed none at all until the user navigated away and back.
@Suite("Ingredient detail — stale references", .serialized)
@MainActor
struct IngredientDetailStaleReferenceTests {

    /// The full schema, not the detail suite's cut-down one: the merger fetches
    /// collections and settings, and `adopt` walks batch and recipe links.
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    private func uuid(_ index: Int) throws -> UUID {
        try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)"))
    }

    /// A row as the installer leaves it, carrying the entry's slug.
    @discardableResult
    private func installed(_ index: Int, in ctx: ModelContext) throws -> Ingredient {
        let row = Ingredient(name: "Olive Butter", unit: IngredientUnit.grams.rawValue)
        row.librarySlug = "olive-butter"
        row.uuid = try uuid(index)
        ctx.insert(row)
        return row
    }

    private func purchase(_ quantity: Double, on ingredient: Ingredient, in ctx: ModelContext) {
        let purchase = IngredientPurchase(
            dateOfPurchase: .now, quantity: quantity, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
        ctx.insert(purchase)
        ingredient.purchases.append(purchase)
    }

    // MARK: - Following the merge

    @Test func resolve_AfterMergeDeletedTheCapturedRow_FollowsTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(1, in: ctx)
        let captured = try installed(2, in: ctx)
        try ctx.save()
        let survivingUUID = keep.uuid

        let model = IngredientDetailViewModel(ingredient: captured)
        try DuplicateMerger.mergeAll(in: ctx)
        #expect(captured.modelContext == nil)

        model.resolve(in: ctx)

        #expect(model.ingredient.uuid == survivingUUID)
        #expect(model.ingredient.modelContext != nil)
    }

    /// The reported symptom: the screen showed no purchases at all, not even the
    /// ones that had synced from the other device.
    @Test func resolve_AfterMergeDeletedTheCapturedRow_PurchasesBecomeVisibleAgain() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(1, in: ctx)
        let captured = try installed(2, in: ctx)
        purchase(111111, on: keep, in: ctx)
        try ctx.save()

        let model = IngredientDetailViewModel(ingredient: captured)
        try DuplicateMerger.mergeAll(in: ctx)

        // Before resolving: the screen is blank even though the purchase exists.
        #expect(model.sortedPurchases.isEmpty)
        #expect(model.totalRemaining == 0)

        model.resolve(in: ctx)

        #expect(model.sortedPurchases.count == 1)
        #expect(model.sortedPurchases.first?.quantity == 111111)
        #expect(model.totalRemaining == 111111)
    }

    @Test func resolve_RowStillInTheStore_KeepsTheSameRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let row = try installed(1, in: ctx)
        purchase(500, on: row, in: ctx)
        try ctx.save()

        let model = IngredientDetailViewModel(ingredient: row)
        model.resolve(in: ctx)

        #expect(model.ingredient === row)
        #expect(model.sortedPurchases.count == 1)
    }

    /// Deleted outright rather than merged, so there is no survivor. The screen
    /// keeps what it has instead of resolving to something unrelated.
    @Test func resolve_RowDeletedWithNoSurvivor_KeepsTheCapturedRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let row = Ingredient(name: "Kokum Butter", unit: IngredientUnit.grams.rawValue)
        row.uuid = try uuid(1)
        ctx.insert(row)
        try ctx.save()

        let model = IngredientDetailViewModel(ingredient: row)
        ctx.delete(row)
        try ctx.save()

        model.resolve(in: ctx)

        #expect(model.ingredient === row)
    }

    /// A user-created row is never merged away, so the screen must not go looking
    /// for a survivor and land on an unrelated library row that shares its name.
    @Test func resolve_UserCreatedRowBesideALibraryTwin_StaysOnItsOwnRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try installed(1, in: ctx)
        let userRow = Ingredient(name: "Olive Butter", unit: IngredientUnit.grams.rawValue)
        userRow.uuid = try uuid(2)
        ctx.insert(userRow)
        purchase(50, on: userRow, in: ctx)
        try ctx.save()

        let model = IngredientDetailViewModel(ingredient: userRow)
        try DuplicateMerger.mergeAll(in: ctx)
        model.resolve(in: ctx)

        #expect(model.ingredient === userRow)
        #expect(model.sortedPurchases.count == 1)
    }

    // MARK: - The notification that drives it

    @Test func mergeAll_WithDeletions_PostsDuplicatesMerged() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        try installed(1, in: ctx)
        try installed(2, in: ctx)
        try ctx.save()

        try await confirmation("duplicatesMerged is posted") { confirmed in
            let token = NotificationCenter.default.addObserver(
                forName: .duplicatesMerged, object: nil, queue: nil
            ) { _ in confirmed() }
            defer { NotificationCenter.default.removeObserver(token) }

            try DuplicateMerger.mergeAll(in: ctx)
        }
    }

    /// The common case by far — every pass after the first finds nothing. A post
    /// here would have every open screen re-resolving for no reason.
    @Test func mergeAll_WithNothingToMerge_PostsNothing() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        try installed(1, in: ctx)
        try ctx.save()

        try await confirmation("nothing is posted", expectedCount: 0) { confirmed in
            let token = NotificationCenter.default.addObserver(
                forName: .duplicatesMerged, object: nil, queue: nil
            ) { _ in confirmed() }
            defer { NotificationCenter.default.removeObserver(token) }

            try DuplicateMerger.mergeAll(in: ctx)
        }
    }
}
