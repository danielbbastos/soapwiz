import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The repairs run on every launch, so on a store with nothing to repair they
/// must do nothing and save nothing (SW-276).
@Suite("Launch repairs on a clean store", .serialized)
@MainActor
struct LaunchRepairNoOpTests {

    private let olive = IngredientLibraryEntry.mock(slug: "olive-oil", name: "Olive Oil", code: "OLO")

    private var library: IngredientLibrary { IngredientLibrary(entries: [olive]) }

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private func makePurchase(on ingredient: Ingredient, in context: ModelContext) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: 500,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        context.insert(purchase)
        purchase.ingredient = ingredient
        return purchase
    }

    // MARK: - Installer

    @Test func installMissing_AfterInstall_ReturnsZeroAndSavesNothing() throws {
        let (container, context) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: library, in: context)

        let changes = try IngredientLibraryInstaller.installMissing(from: library, in: context)

        #expect(changes == 0)
        #expect(!context.hasChanges)
    }

    // MARK: - Code backfill

    @Test func fillMissingCodes_CleanStore_ReturnsZeroAndSavesNothing() throws {
        let (container, context) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: library, in: context)
        let custom = Ingredient(name: "My Blend", unit: "g")
        context.insert(custom)
        try context.save()

        let filled = try IngredientCodeBackfill.fillMissingCodes(from: library, in: context)

        #expect(filled == 0)
        #expect(!context.hasChanges)
    }

    @Test func fillMissingCodes_OnlyUserRowWithoutCode_ReturnsZero() throws {
        let (container, context) = try makeContext()
        _ = container
        let custom = Ingredient(name: "My Blend", unit: "g")
        context.insert(custom)
        try context.save()

        let filled = try IngredientCodeBackfill.fillMissingCodes(from: library, in: context)

        #expect(filled == 0)
        #expect(custom.code.isEmpty)
    }

    // MARK: - Identity backfills

    @Test func ingredientIdentity_DistinctUuids_ReturnsZeroAndSavesNothing() throws {
        let (container, context) = try makeContext()
        _ = container
        context.insert(Ingredient(name: "Olive Oil", unit: "g"))
        context.insert(Ingredient(name: "Lye", unit: "g"))
        try context.save()

        let repaired = try IngredientIdentityBackfill.repairSharedIdentities(in: context)

        #expect(repaired == 0)
        #expect(!context.hasChanges)
    }

    @Test func recipeIdentity_DistinctUuids_ReturnsZeroAndSavesNothing() throws {
        let (container, context) = try makeContext()
        _ = container
        context.insert(Recipe(name: "Bastille"))
        context.insert(Recipe(name: "Castile"))
        try context.save()

        let repaired = try RecipeIdentityBackfill.repairSharedIdentities(in: context)

        #expect(repaired == 0)
        #expect(!context.hasChanges)
    }

    // MARK: - Link repair

    @Test func stampSlugs_AlreadyStamped_ReturnsFalse() throws {
        let (container, context) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.librarySlug = "olive-oil"
        context.insert(ingredient)
        let purchase = makePurchase(on: ingredient, in: context)
        purchase.ingredientSlug = "olive-oil"
        try context.save()

        #expect(try IngredientLinkRepair.stampSlugs(in: context) == false)
        #expect(!context.hasChanges)
    }

    @Test func stampSlugs_StaleSlug_IsStamped() throws {
        let (container, context) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.librarySlug = "olive-oil"
        context.insert(ingredient)
        let purchase = makePurchase(on: ingredient, in: context)
        purchase.ingredientSlug = ""
        try context.save()

        #expect(try IngredientLinkRepair.stampSlugs(in: context))
        #expect(purchase.ingredientSlug == "olive-oil")
    }

    @Test func stampSlugs_RowWithoutIngredient_IsLeftAlone() throws {
        let (container, context) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.librarySlug = "olive-oil"
        context.insert(ingredient)
        let purchase = makePurchase(on: ingredient, in: context)
        purchase.ingredientSlug = "olive-oil"
        purchase.ingredient = nil
        try context.save()

        #expect(try IngredientLinkRepair.stampSlugs(in: context) == false)
        #expect(purchase.ingredientSlug == "olive-oil")
    }

    @Test func reattachDetachedRows_NothingDetached_ReturnsFalse() throws {
        let (container, context) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.librarySlug = "olive-oil"
        context.insert(ingredient)
        _ = makePurchase(on: ingredient, in: context)
        try context.save()

        #expect(try IngredientLinkRepair.reattachDetachedRows(in: context) == false)
    }

    @Test func reattachDetachedRows_DetachedPurchase_GoesBackToSurvivor() throws {
        let (container, context) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.librarySlug = "olive-oil"
        context.insert(ingredient)
        let purchase = makePurchase(on: ingredient, in: context)
        purchase.ingredientSlug = "olive-oil"
        purchase.ingredient = nil
        try context.save()

        #expect(try IngredientLinkRepair.reattachDetachedRows(in: context))
        #expect(purchase.ingredient === ingredient)
    }

    // MARK: - Whole merge

    @Test func mergeAll_CleanStore_SavesNothing() throws {
        let (container, context) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: library, in: context)

        try DuplicateMerger.mergeAll(in: context)

        #expect(!context.hasChanges)
    }
}
