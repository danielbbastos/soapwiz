import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Ingredients duplicate for a reason the other lookup rows don't share: every
/// device installs the bundled library before sync can tell it the account
/// already has one. Those copies collapse by `librarySlug`; a row the user
/// created carries no slug and is deliberately left alone.
@Suite("Duplicate merger — ingredients", .serialized)
@MainActor
struct DuplicateMergerIngredientTests: DuplicateMergerIngredientHelpers {

    // MARK: - Slug pass: repointing

    /// Everything that can point at an ingredient has to survive the collapse.
    /// A missed link is a purchase, a recipe or a batch losing its ingredient.
    @Test func mergeAll_TwoRowsWithSameSlug_CollapseAndRepointEverything() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(olive, 1)
        let drop = try installed(olive, 2)
        ctx.insert(keep)
        ctx.insert(drop)

        let purchase = IngredientPurchase.mock(quantity: 500)
        purchase.ingredient = drop
        ctx.insert(purchase)

        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)
        let recipeIngredient = RecipeIngredient(ingredient: drop, percentage: 100)
        recipeIngredient.recipe = recipe
        ctx.insert(recipeIngredient)
        recipe.lyeIngredient = drop
        recipe.kohLyeIngredient = drop

        let lineItem = BatchLineItem(
            ingredient: drop,
            ingredientName: "Olive Oil",
            amountConsumed: 100,
            unit: IngredientUnit.grams.rawValue,
            cost: 2,
            draws: []
        )
        ctx.insert(lineItem)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let remaining = try ingredients(ctx)
        #expect(remaining.count == 1)
        #expect(remaining.first?.uuid == keep.uuid)
        #expect(purchase.ingredient?.uuid == keep.uuid)
        #expect(recipeIngredient.ingredient?.uuid == keep.uuid)
        #expect(lineItem.ingredient?.uuid == keep.uuid)
        #expect(recipe.lyeIngredient?.uuid == keep.uuid)
        #expect(recipe.kohLyeIngredient?.uuid == keep.uuid)
        #expect(keep.purchases.count == 1)
    }

    /// The test the whole convergence design exists for. Two devices hold the
    /// same synced rows in different local order and with different amounts of
    /// the import applied. Disagree about the winner and both delete the other's,
    /// losing the ingredient entirely.
    @Test func mergeAll_TwoDevicesDisagreeingOnOrder_KeepTheSameWinner() throws {
        func survivorUUID(insertingInReverse reversed: Bool) throws -> UUID {
            let (container, ctx) = try makeContext()
            _ = container
            let one = try installed(olive, 1)
            let two = try installed(olive, 2)
            for row in reversed ? [two, one] : [one, two] {
                ctx.insert(row)
            }
            if reversed {
                let purchase = IngredientPurchase.mock(quantity: 250)
                purchase.ingredient = two
                ctx.insert(purchase)
            }
            try ctx.save()

            try DuplicateMerger.mergeAll(in: ctx)

            let remaining = try ingredients(ctx)
            #expect(remaining.count == 1)
            return try #require(remaining.first?.uuid)
        }

        let deviceA = try survivorUUID(insertingInReverse: false)
        let deviceB = try survivorUUID(insertingInReverse: true)
        let lowest = try uuid(1)

        #expect(deviceA == deviceB)
        #expect(deviceA == lowest)
    }

    @Test func mergeAll_DistinctSlugs_AreLeftAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(try installed(olive, 1))
        ctx.insert(try installed(coconut, 2))
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(try ingredients(ctx).count == 2)
        #expect(ctx.hasChanges == false)
    }

    // MARK: - Slug pass: folding the name

    /// A rename is the user's. Both devices installed the row under the entry's
    /// name, so the copy still carrying it was never touched and yields to the
    /// one that was — otherwise the rename is lost whenever the renamed copy
    /// drew the higher `uuid`.
    @Test func mergeAll_LoserWasRenamed_WinnerTakesTheRename() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let winner = try installed(olive, 1)
        let renamed = try installed(olive, 2)
        renamed.name = "EVOO"
        ctx.insert(winner)
        ctx.insert(renamed)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let rows = try ingredients(ctx)
        #expect(rows.count == 1)
        let survivor = try #require(rows.first)
        #expect(survivor.uuid == winner.uuid)
        #expect(survivor.name == "EVOO")
    }

    /// The rename is already on the winner, and the untouched copy's catalog
    /// name must not be folded back over it.
    @Test func mergeAll_WinnerWasRenamed_KeepsItsOwnName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let winner = try installed(olive, 1)
        winner.name = "EVOO"
        ctx.insert(winner)
        ctx.insert(try installed(olive, 2))
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let rows = try ingredients(ctx)
        #expect(rows.count == 1)
        #expect(rows.first?.name == "EVOO")
    }

    /// Renamed on both devices: neither name is the catalog's, so the lowest
    /// `uuid` decides, as it does everywhere else.
    @Test func mergeAll_BothCopiesRenamed_WinnerKeepsItsOwnName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let winner = try installed(olive, 1)
        winner.name = "EVOO"
        let other = try installed(olive, 2)
        other.name = "Olive, extra virgin"
        ctx.insert(winner)
        ctx.insert(other)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let rows = try ingredients(ctx)
        #expect(rows.count == 1)
        #expect(rows.first?.name == "EVOO")
    }

    // MARK: - Slug pass: folding fields

    /// The customised copy is the only one holding values the user chose, so it
    /// hands them to a winner still carrying the bundled ones.
    @Test func mergeAll_LoserHasCustomChemistry_WinnerTakesItAndTheFlag() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(olive, 1)
        let drop = try installed(olive, 2)
        drop.sapValue = 0.1405
        drop.density = 0.918
        drop.hasCustomChemistry = true
        ctx.insert(keep)
        ctx.insert(drop)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let survivor = try #require(try ingredients(ctx).first)
        #expect(survivor.uuid == keep.uuid)
        #expect(survivor.hasCustomChemistry)
        #expect(survivor.sapValue == 0.1405)
        #expect(survivor.density == 0.918)
        #expect(!survivor.isPristineLibraryRow)
    }

    @Test func mergeAll_BothCopiesCustomised_WinnerKeepsItsOwnChemistry() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(olive, 1)
        keep.sapValue = 0.1340
        keep.hasCustomChemistry = true
        let drop = try installed(olive, 2)
        drop.sapValue = 0.1405
        drop.hasCustomChemistry = true
        ctx.insert(keep)
        ctx.insert(drop)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let survivor = try #require(try ingredients(ctx).first)
        #expect(survivor.sapValue == 0.1340)
        #expect(survivor.hasCustomChemistry)
    }

    /// Both flags are opt-in, so they join rather than being decided by whichever
    /// row happened to win.
    @Test func mergeAll_HiddenOrFavouriteOnEitherCopy_SurvivesTheMerge() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(olive, 1)
        let drop = try installed(olive, 2)
        drop.isHidden = true
        drop.isFavorite = true
        ctx.insert(keep)
        ctx.insert(drop)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let survivor = try #require(try ingredients(ctx).first)
        #expect(survivor.isHidden)
        #expect(survivor.isFavorite)
    }

    @Test func mergeAll_WinnerMissingOptionalFields_TakesThemFromTheLoser() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(olive, 1)
        let drop = try installed(olive, 2)
        drop.imageData = Data([0x01, 0x02])
        drop.thumbnailData = Data([0x03])
        drop.code = "OO-01"
        drop.lowStockThreshold = 250
        ctx.insert(keep)
        ctx.insert(drop)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let survivor = try #require(try ingredients(ctx).first)
        #expect(survivor.imageData == Data([0x01, 0x02]))
        #expect(survivor.thumbnailData == Data([0x03]))
        #expect(survivor.code == "OO-01")
        #expect(survivor.lowStockThreshold == 250)
    }

    /// The thumbnail is derived from the photo, so a winner that already has one
    /// must keep both — mixing them shows a thumbnail of a different bottle.
    @Test func mergeAll_WinnerHasItsOwnPhoto_KeepsBothHalvesOfIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(olive, 1)
        keep.imageData = Data([0xAA])
        keep.thumbnailData = Data([0xBB])
        keep.code = "KEEP"
        keep.lowStockThreshold = 100
        let drop = try installed(olive, 2)
        drop.imageData = Data([0x01])
        drop.thumbnailData = Data([0x02])
        drop.code = "DROP"
        drop.lowStockThreshold = 999
        ctx.insert(keep)
        ctx.insert(drop)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let survivor = try #require(try ingredients(ctx).first)
        #expect(survivor.imageData == Data([0xAA]))
        #expect(survivor.thumbnailData == Data([0xBB]))
        #expect(survivor.code == "KEEP")
        #expect(survivor.lowStockThreshold == 100)
    }
}
