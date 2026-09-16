import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The rows the ingredient merge must not touch, and the guarantee that a second
/// pass finds nothing left to do.
///
/// Split from `DuplicateMergerIngredientTests`, which covers the slug pass, so
/// neither file outgrows the 400-line limit. Both share their fixtures through
/// `DuplicateMergerIngredientHelpers`.
@Suite("Duplicate merger — ingredients left alone", .serialized)
@MainActor
struct DuplicateMergerIngredientScopeTests: DuplicateMergerIngredientHelpers {

    /// The merge used to fold a slug-less row into the library row whose entry
    /// claimed its name, and deleting it took the user's purchases with it —
    /// the SW-136 data loss. A row the user made deliberately is not a duplicate
    /// of a catalog entry just because the names agree, so it stays.
    ///
    /// Linking such a row to an entry is `IngredientLibraryInstaller`'s job, and
    /// it only does so while no row carries that slug yet, so it never deletes
    /// anything. See SW-140.
    @Test func mergeAll_SlugLessRowMatchingAnEntryName_IsKeptWithItsPurchases() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let libraryRow = try installed(olive, 2)
        ctx.insert(libraryRow)

        let userRow = Ingredient.mock(matching: olive, name: "  olive  oil ")
        userRow.uuid = try uuid(1)
        ctx.insert(userRow)
        let purchase = IngredientPurchase.mock(quantity: 500)
        purchase.ingredient = userRow
        ctx.insert(purchase)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(try ingredients(ctx).count == 2)
        #expect(userRow.librarySlug.isEmpty)
        #expect(purchase.ingredient?.uuid == userRow.uuid)
        #expect(userRow.purchases.count == 1)
        #expect(ctx.hasChanges == false)
    }

    /// Aliases are a recognition hint for the installer, never a licence for the
    /// merge to delete the row that matches one.
    @Test func mergeAll_SlugLessRowMatchingAnAlias_IsKept() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(try installed(olive, 1))
        let userRow = Ingredient.mock(matching: olive, name: "EVOO")
        userRow.uuid = try uuid(2)
        userRow.code = "EVOO"
        ctx.insert(userRow)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(try ingredients(ctx).count == 2)
        #expect(userRow.name == "EVOO")
        #expect(userRow.code == "EVOO")
        #expect(ctx.hasChanges == false)
    }

    /// The user's own SAP value is the reason they made the row, and it stays on
    /// the row they made rather than being folded onto a library one.
    @Test func mergeAll_SlugLessRowWithItsOwnChemistry_KeepsItOnItsOwnRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(try installed(olive, 1))
        let userRow = Ingredient.mock(matching: olive, name: "Olive Oil")
        userRow.uuid = try uuid(2)
        userRow.sapValue = 0.1405
        ctx.insert(userRow)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(try ingredients(ctx).count == 2)
        #expect(userRow.sapValue == 0.1405)
        #expect(ctx.hasChanges == false)
    }

    /// Nothing to fold into: installing the slug is the installer's job, and the
    /// merger must not invent one.
    @Test func mergeAll_EntryWithNoInstalledRow_LeavesTheSlugLessRowAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let userRow = Ingredient.mock(matching: coconut)
        userRow.uuid = try uuid(1)
        ctx.insert(userRow)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(try ingredients(ctx).count == 1)
        #expect(userRow.librarySlug.isEmpty)
        #expect(ctx.hasChanges == false)
    }

    /// Unlike a category, an ingredient carries purchases and batch history, so
    /// two the user happened to name alike are not fused behind their back.
    /// See SW-140.
    @Test func mergeAll_UserCreatedIngredientsSharingAName_AreBothKept() throws {
        let (container, ctx) = try makeContext()
        _ = container
        for (index, name) in ["Lard", "lard"].enumerated() {
            let ingredient = Ingredient(name: name, unit: IngredientUnit.grams.rawValue)
            ingredient.uuid = try uuid(index + 1)
            ctx.insert(ingredient)
        }
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(try ingredients(ctx).count == 2)
        #expect(ctx.hasChanges == false)
    }

    // MARK: - Idempotency

    @Test func mergeAll_RunTwice_SecondPassChangesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(try installed(olive, 1))
        ctx.insert(try installed(olive, 2))
        let userRow = Ingredient.mock(matching: olive, name: "EVOO")
        userRow.uuid = try uuid(3)
        ctx.insert(userRow)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)
        let afterFirst = try ingredients(ctx).map(\.uuid)

        try DuplicateMerger.mergeAll(in: ctx)
        let afterSecond = try ingredients(ctx).map(\.uuid)

        #expect(afterFirst == afterSecond)
        // The two slug copies collapse to one; the slug-less row is untouched.
        #expect(afterFirst.count == 2)
        #expect(ctx.hasChanges == false)
    }

    @Test func mergeAll_NoIngredients_DoesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(try ingredients(ctx).isEmpty)
        #expect(ctx.hasChanges == false)
    }
}
