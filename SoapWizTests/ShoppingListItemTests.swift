import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The shopping list line (SW-353): it outlives its ingredient, follows the
/// duplicate merge, finds its way back after a sync race, and rides in backups.
@Suite("Shopping list item", .serialized)
@MainActor
struct ShoppingListItemTests: DuplicateMergerIngredientHelpers {

    private func roundTripInPlace(_ ctx: ModelContext) throws {
        let backup = try BackupService.makeBackup(from: ctx)
        let decoded = try BackupService.decode(try BackupService.encode(backup))
        try BackupService.restore(decoded, into: ctx)
    }

    private func items(_ ctx: ModelContext) throws -> [ShoppingListItem] {
        try ctx.fetch(FetchDescriptor<ShoppingListItem>())
    }

    // MARK: - Model

    @Test func init_Defaults_AreUncheckedAndUnlinked() {
        let item = ShoppingListItem(name: "Shea Butter")

        #expect(item.amount == nil)
        #expect(item.unit.isEmpty)
        #expect(item.ingredient == nil)
        #expect(item.ingredientSlug.isEmpty)
        #expect(item.isChecked == false)
        #expect(item.checkedAt == nil)
    }

    @Test func init_WithLibraryIngredient_StampsItsSlug() throws {
        let ingredient = try installed(coconut, 1)

        let item = ShoppingListItem(name: ingredient.name, amount: 500, unit: "g", ingredient: ingredient)

        #expect(item.ingredientSlug == "coconut-oil")
    }

    // MARK: - Deletion

    @Test func contextDelete_Ingredient_KeepsItemUnlinked() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        ctx.insert(ShoppingListItem(name: "Olive Oil", amount: 1000, unit: "g", ingredient: oil))
        try ctx.save()

        ctx.delete(oil)
        try ctx.save()

        let remaining = try items(ctx)
        #expect(remaining.count == 1)
        #expect(remaining.first?.ingredient == nil)
        #expect(remaining.first?.name == "Olive Oil")
    }

    @Test func deleteWithOwnedRows_Ingredient_KeepsItemUnlinked() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        ctx.insert(ShoppingListItem(name: "Olive Oil", amount: 1000, unit: "g", ingredient: oil))
        try ctx.save()

        oil.deleteWithOwnedRows(in: ctx)
        try ctx.save()

        let remaining = try items(ctx)
        #expect(remaining.count == 1)
        #expect(remaining.first?.ingredient == nil)
    }

    // MARK: - Duplicate merge

    @Test func mergeAll_LoserHasItems_MovesThemToTheWinner() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(coconut, 1)
        let lose = try installed(coconut, 2)
        ctx.insert(keep)
        ctx.insert(lose)
        let item = ShoppingListItem(name: "Coconut Oil", ingredient: lose)
        ctx.insert(item)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(item.ingredient?.uuid == keep.uuid)
        #expect(keep.shoppingListItems.count == 1)
        #expect(try items(ctx).count == 1)
    }

    // MARK: - Link repair

    @Test func mergeAll_LoserDeletedBeforeRepointArrives_ItemLandsOnTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let local = try installed(coconut, 2)
        ctx.insert(local)
        let item = ShoppingListItem(name: "Coconut Oil", ingredient: local)
        ctx.insert(item)
        try DuplicateMerger.mergeAll(in: ctx)

        let remote = try installed(coconut, 1)
        ctx.insert(remote)
        ctx.delete(local)
        try ctx.save()
        #expect(item.ingredient == nil)

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(item.ingredient?.uuid == remote.uuid)
        #expect(try items(ctx).count == 1)
    }

    @Test func mergeAll_UnlinkedItem_StaysUnlinked() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed(coconut, 1)
        ctx.insert(oil)
        let item = ShoppingListItem(name: "Candle wicks")
        ctx.insert(item)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(item.ingredient == nil)
    }

    @Test func reattachDetachedRows_OnlyManualItem_ReturnsFalseAndStaysUnlinked() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed(coconut, 1)
        ctx.insert(oil)
        let item = ShoppingListItem(name: "Candle wicks")
        ctx.insert(item)
        try ctx.save()

        #expect(try IngredientLinkRepair.reattachDetachedRows(in: ctx) == false)
        #expect(item.ingredient == nil)
    }

    // MARK: - Backup

    private func seedItems(_ ctx: ModelContext) throws {
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        oil.librarySlug = "olive-oil"
        ctx.insert(oil)
        let linked = ShoppingListItem(name: "Olive Oil", amount: 1500, unit: "g", ingredient: oil, note: "the big tin")
        linked.isChecked = true
        linked.checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        linked.createdAt = Date(timeIntervalSince1970: 1_690_000_000)
        ctx.insert(linked)
        ctx.insert(ShoppingListItem(name: "Candle wicks"))
        try ctx.save()
    }

    @Test func roundTrip_PreservesItemsFieldsAndLinks() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedItems(ctx)

        try roundTripInPlace(ctx)

        let restored = try items(ctx)
        #expect(restored.count == 2)
        let linked = try #require(restored.first { $0.name == "Olive Oil" })
        #expect(linked.ingredient?.name == "Olive Oil")
        #expect(linked.ingredientSlug == "olive-oil")
        #expect(linked.amount == 1500)
        #expect(linked.unit == "g")
        #expect(linked.note == "the big tin")
        #expect(linked.isChecked)
        #expect(linked.checkedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(linked.createdAt == Date(timeIntervalSince1970: 1_690_000_000))
    }

    @Test func roundTrip_UnlinkedItem_StaysUnlinked() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedItems(ctx)

        try roundTripInPlace(ctx)

        let wicks = try #require(try items(ctx).first { $0.name == "Candle wicks" })
        #expect(wicks.ingredient == nil)
        #expect(wicks.amount == nil)
        #expect(wicks.isChecked == false)
    }

    @Test func restore_BackupWithoutKey_RestoresNoItems() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedItems(ctx)
        var backup = try BackupService.makeBackup(from: ctx)
        backup.shoppingList = nil
        let decoded = try BackupService.decode(try BackupService.encode(backup))
        #expect(decoded.shoppingList == nil)

        try BackupService.restore(decoded, into: ctx)

        #expect(try items(ctx).isEmpty)
    }

    @Test func isEmpty_OnlyShoppingList_IsNotEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(ShoppingListItem(name: "Candle wicks"))
        try ctx.save()

        let backup = try BackupService.makeBackup(from: ctx)

        #expect(backup.isEmpty == false)
    }

    @Test func wipe_DeletesItems() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedItems(ctx)

        try BackupService.wipe(ctx)
        try ctx.save()

        #expect(try items(ctx).isEmpty)
    }
}
