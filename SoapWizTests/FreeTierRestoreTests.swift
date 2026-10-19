import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Free tier restore", .serialized)
@MainActor
struct FreeTierRestoreTests: RestoreTestCase {

    private func makeBackup(
        recipes: Int = 0,
        custom: Int = 0,
        library: Int = 0,
        renamedLibrary: Int = 0
    ) throws -> BackupData {
        let (container, ctx) = try makeContext()
        _ = container
        for index in 0..<recipes {
            ctx.insert(Recipe(name: "Recipe \(index)", desc: ""))
        }
        for index in 0..<custom {
            ctx.insert(Ingredient(name: "Custom \(index)", unit: "g"))
        }
        let entries = Array(IngredientLibrary.bundled.entries.prefix(library + renamedLibrary))
        try #require(entries.count == library + renamedLibrary)
        for (index, entry) in entries.enumerated() {
            let ingredient = Ingredient(name: index < library ? entry.name : "Mine \(entry.name)", unit: "g")
            ingredient.librarySlug = entry.slug
            ctx.insert(ingredient)
        }
        try ctx.save()
        return try BackupService.makeBackup(from: ctx)
    }

    // MARK: restoreFits

    @Test func restoreFits_UnderCaps_ReturnsTrue() {
        #expect(FreeTierLimits.restoreFits(recipes: 1, customIngredients: 2, isPro: false))
    }

    @Test func restoreFits_ExactlyAtCaps_ReturnsTrue() {
        #expect(FreeTierLimits.restoreFits(
            recipes: FreeTierLimits.recipeCap,
            customIngredients: FreeTierLimits.customIngredientCap,
            isPro: false
        ))
    }

    @Test func restoreFits_OneRecipeOver_ReturnsFalse() {
        #expect(!FreeTierLimits.restoreFits(
            recipes: FreeTierLimits.recipeCap + 1,
            customIngredients: 0,
            isPro: false
        ))
    }

    @Test func restoreFits_OneCustomIngredientOver_ReturnsFalse() {
        #expect(!FreeTierLimits.restoreFits(
            recipes: 0,
            customIngredients: FreeTierLimits.customIngredientCap + 1,
            isPro: false
        ))
    }

    @Test func restoreFits_Pro_AlwaysFits() {
        #expect(FreeTierLimits.restoreFits(recipes: 500, customIngredients: 500, isPro: true))
    }

    // MARK: Counting a backup

    @Test func customIngredientCount_UnrenamedLibraryRows_AreNotCounted() throws {
        let backup = try makeBackup(library: 5)
        #expect(FreeTierLimits.customIngredientCount(in: backup) == 0)
        #expect(FreeTierLimits.restoreFits(backup, isPro: false))
    }

    @Test func customIngredientCount_RenamedLibraryRow_IsCounted() throws {
        let backup = try makeBackup(library: 2, renamedLibrary: 1)
        #expect(FreeTierLimits.customIngredientCount(in: backup) == 1)
    }

    @Test func customIngredientCount_MissingSlug_IsCounted() throws {
        let backup = try makeBackup(custom: 2)
        #expect(FreeTierLimits.customIngredientCount(in: backup) == 2)
    }

    @Test func restoreFits_BackupWithRenamedLibraryRowsOverCap_ReturnsFalse() throws {
        let backup = try makeBackup(renamedLibrary: FreeTierLimits.customIngredientCap + 1)
        #expect(!FreeTierLimits.restoreFits(backup, isPro: false))
        #expect(FreeTierLimits.restoreFits(backup, isPro: true))
    }

    @Test func restoreFits_BackupAtCaps_ReturnsTrue() throws {
        let backup = try makeBackup(
            recipes: FreeTierLimits.recipeCap,
            custom: FreeTierLimits.customIngredientCap
        )
        #expect(FreeTierLimits.restoreFits(backup, isPro: false))
    }

    // MARK: The restore path

    @Test func stage_OverCapBackupForFreeUser_StagesNothing() throws {
        let backup = try makeBackup(recipes: FreeTierLimits.recipeCap + 1)
        let coordinator = makeCoordinator()

        let staged = coordinator.stage(backup, isPro: false)

        #expect(!staged)
        #expect(coordinator.pendingImport == nil)
    }

    @Test func stage_OverCapBackupForPro_Stages() throws {
        let backup = try makeBackup(recipes: FreeTierLimits.recipeCap + 1)
        let coordinator = makeCoordinator()

        #expect(coordinator.stage(backup, isPro: true))
        #expect(coordinator.pendingImport != nil)
    }

    @Test func perform_OverCapBackupForFreeUser_LeavesTheStoreUnchanged() async throws {
        let backup = try makeBackup(recipes: FreeTierLimits.recipeCap + 1)
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")
        let directory = try makeRollbackDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let coordinator = makeCoordinator()
        coordinator.rollbackDirectory = directory
        coordinator.stage(backup, isPro: true)
        coordinator.begin(navigation: AppNavigation())
        await coordinator.perform(in: ctx, isPro: false)
        await coordinator.outcomeTask?.value

        #expect(coordinator.errorMessage != nil)
        #expect(coordinator.rollbackFile == nil)
        #expect(coordinator.phase == .idle)
        #expect(try ctx.fetch(FetchDescriptor<Recipe>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.name) == ["Olive Oil"])
        #expect(try rollbackFiles(in: directory).isEmpty)
    }

    @Test func restore_OverCapBackupForFreeUser_LeavesTheStoreUnchanged() async throws {
        let backup = try makeBackup(custom: FreeTierLimits.customIngredientCap + 1)
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let coordinator = makeCoordinator()
        await restore(backup, with: coordinator, into: ctx, isPro: false)

        #expect(coordinator.pendingImport == nil)
        #expect(coordinator.generation == 0)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.name) == ["Olive Oil"])
    }

    @Test func perform_OverCapBackupForPro_Restores() async throws {
        let backup = try makeBackup(recipes: FreeTierLimits.recipeCap + 1)
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")
        let directory = try makeRollbackDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let coordinator = makeCoordinator()
        coordinator.rollbackDirectory = directory
        await restore(backup, with: coordinator, into: ctx, isPro: true)

        #expect(try ctx.fetch(FetchDescriptor<Recipe>()).count == FreeTierLimits.recipeCap + 1)
    }
}
