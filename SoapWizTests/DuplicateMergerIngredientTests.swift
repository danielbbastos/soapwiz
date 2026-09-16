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
struct DuplicateMergerIngredientTests {

    private let olive = IngredientLibraryEntry.mock(
        slug: "olive-oil",
        name: "Olive Oil",
        aliases: ["Extra Virgin Olive Oil", "EVOO"]
    )
    private let coconut = IngredientLibraryEntry.mock(
        slug: "coconut-oil",
        name: "Coconut Oil",
        sapValue: 0.183,
        kohSapValue: 0.257,
        density: 0.921,
        fattyAcidProfile: FattyAcidProfile(lauric: 48, myristic: 19, palmitic: 9, stearic: 3, oleic: 8, linoleic: 2)
    )

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

    /// A row as the installer leaves it: the entry's name, unit and chemistry,
    /// carrying its slug.
    private func installed(_ entry: IngredientLibraryEntry, _ index: Int) throws -> Ingredient {
        let ingredient = Ingredient.mock(matching: entry)
        ingredient.librarySlug = entry.slug
        ingredient.uuid = try uuid(index)
        return ingredient
    }

    private func ingredients(_ ctx: ModelContext) throws -> [Ingredient] {
        try ctx.fetch(FetchDescriptor<Ingredient>())
    }

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
        #expect(!survivor.isLibrary)
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

    // MARK: - Rows the merge deliberately leaves alone

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
