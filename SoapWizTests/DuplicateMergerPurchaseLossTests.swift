import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Regression guard for the purchase lost during the SW-136 device test.
///
/// A sheet captures an `Ingredient` when it opens. The duplicate merge deletes
/// that row and saves, leaving the captured reference detached — and `isDeleted`
/// reads `false` on it, so the write site cannot tell. Appending a purchase to it
/// then loses the purchase outright rather than orphaning it, because
/// `Ingredient.purchases` cascades and the new row goes down with the dead
/// parent. That is exactly what the device showed: purchase count unchanged, no
/// row with a nil ingredient.
///
/// These drive the real `PurchaseFormViewModel`, not a replica of it, so the
/// guard cannot drift away from what the form actually does.
@Suite("Stale ingredient references — purchase loss", .serialized)
@MainActor
struct DuplicateMergerPurchaseLossTests {

    private let olive = IngredientLibraryEntry.mock(slug: "olive-oil", name: "Olive Oil")

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

    /// A row as the installer leaves it: the entry's chemistry, carrying its slug.
    private func installed(_ index: Int, in ctx: ModelContext) throws -> Ingredient {
        let row = Ingredient.mock(matching: olive)
        row.librarySlug = olive.slug
        row.uuid = try uuid(index)
        ctx.insert(row)
        return row
    }

    /// The form as the user drives it: open the sheet on `ingredient`, type a
    /// quantity, tap Add.
    private func addPurchase(
        to ingredient: Ingredient,
        quantity: String = "500",
        in ctx: ModelContext
    ) throws {
        let model = PurchaseFormViewModel(ingredient: ingredient)
        model.quantityText = quantity
        try model.save(context: ctx)
    }

    private func purchases(_ ctx: ModelContext) throws -> [IngredientPurchase] {
        try ctx.fetch(FetchDescriptor<IngredientPurchase>())
    }

    // MARK: - The stale sheet

    /// The device scenario. Two copies of one library row arrive, the sheet is
    /// opened on the copy the merge is about to delete, and the user taps Add
    /// after it has gone.
    @Test func save_AfterMergeDeletedTheCapturedIngredient_PurchaseLandsOnTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(1, in: ctx)
        let captured = try installed(2, in: ctx)
        try ctx.save()
        let survivingUUID = keep.uuid

        try DuplicateMerger.mergeAll(in: ctx)
        // The signal the write site actually keys on. `isDeleted` would say false.
        #expect(captured.modelContext == nil)

        try addPurchase(to: captured, in: ctx)
        try ctx.save()

        let saved = try purchases(ctx)
        #expect(saved.count == 1)
        #expect(saved.first?.ingredient?.uuid == survivingUUID)
        #expect(saved.first?.quantity == 500)
    }

    /// The autosave window: the purchase is inserted but not yet committed when
    /// the merge fires on the same context. This passed before the fix and must
    /// keep passing — the merge repoints a pending insert correctly.
    @Test func save_ThenMergeRunsBeforeAutosave_PurchaseIsRepointedToTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(1, in: ctx)
        let captured = try installed(2, in: ctx)
        try ctx.save()
        let survivingUUID = keep.uuid

        try addPurchase(to: captured, in: ctx)
        try DuplicateMerger.mergeAll(in: ctx)

        let saved = try purchases(ctx)
        #expect(saved.count == 1)
        #expect(saved.first?.ingredient?.uuid == survivingUUID)
    }

    /// Nothing to recover to: the row was deleted outright rather than merged, so
    /// no survivor carries its slug. The write must fail loudly instead of
    /// vanishing — and must not leave a half-written purchase behind.
    @Test func save_CapturedIngredientDeletedWithNoSurvivor_ThrowsAndWritesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let userRow = Ingredient(name: "Kokum Butter", unit: IngredientUnit.grams.rawValue)
        userRow.uuid = try uuid(1)
        ctx.insert(userRow)
        try ctx.save()

        ctx.delete(userRow)
        try ctx.save()

        let model = PurchaseFormViewModel(ingredient: userRow)
        model.quantityText = "500"
        #expect(throws: PurchaseSaveError.self) {
            try model.save(context: ctx)
        }
        #expect(try purchases(ctx).isEmpty)
    }

    /// The ordinary path, so the guard above cannot pass by refusing everything.
    @Test func save_IngredientStillInTheStore_AddsThePurchaseToIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let row = try installed(1, in: ctx)
        try ctx.save()

        try addPurchase(to: row, in: ctx)
        try ctx.save()

        let saved = try purchases(ctx)
        #expect(saved.count == 1)
        #expect(saved.first?.ingredient?.uuid == row.uuid)
    }

    /// Editing an existing purchase never touches the ingredient relationship, so
    /// it has no stale-reference exposure and must keep working unchanged.
    @Test func save_EditingAnExistingPurchase_DoesNotNeedTheIngredient() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let row = try installed(1, in: ctx)
        let purchase = IngredientPurchase.mock(quantity: 100)
        purchase.ingredient = row
        ctx.insert(purchase)
        try ctx.save()

        let model = PurchaseFormViewModel(ingredient: row, purchase: purchase)
        model.quantityText = "250"
        try model.save(context: ctx)

        #expect(purchase.quantity == 250)
        #expect(try purchases(ctx).count == 1)
    }

    // MARK: - The resolver itself

    @Test func resolve_IngredientStillInAContext_ReturnsTheSameRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let row = try installed(1, in: ctx)
        try ctx.save()

        let resolved = LiveIngredient.resolve(row, slug: row.librarySlug, in: ctx)

        #expect(resolved?.persistentModelID == row.persistentModelID)
    }

    @Test func resolve_RowMergedAway_ReturnsTheSurvivorCarryingTheSlug() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(1, in: ctx)
        let drop = try installed(2, in: ctx)
        try ctx.save()
        let survivingUUID = keep.uuid

        try DuplicateMerger.mergeAll(in: ctx)
        let resolved = LiveIngredient.resolve(drop, slug: olive.slug, in: ctx)

        #expect(resolved?.uuid == survivingUUID)
    }

    /// A user-created row has no slug, so there is nothing to resolve it to and
    /// the resolver must not fall back to guessing by name.
    @Test func resolve_DeletedRowWithNoSlug_ReturnsNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let row = Ingredient(name: "Olive Oil", unit: IngredientUnit.grams.rawValue)
        ctx.insert(row)
        try ctx.save()
        ctx.delete(row)
        try ctx.save()

        #expect(LiveIngredient.resolve(row, slug: "", in: ctx) == nil)
    }
}
