import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Free tier restore", .serialized)
@MainActor
struct FreeTierRestoreTests: RestoreTestCase {

    private func makeBackup(
        recipes: Int = 0,
        custom: Int = 0
    ) throws -> BackupData {
        let (container, ctx) = try makeContext()
        _ = container
        for index in 0..<recipes {
            ctx.insert(Recipe(name: "Recipe \(index)", desc: ""))
        }
        for index in 0..<custom {
            ctx.insert(Ingredient(name: "Custom \(index)", unit: "g"))
        }
        try ctx.save()
        return try BackupService.makeBackup(from: ctx)
    }

    // MARK: restoreFits

    @Test func restoreFits_UnderCap_ReturnsTrue() {
        #expect(FreeTierLimits.restoreFits(recipes: 1, isPro: false))
    }

    @Test func restoreFits_ExactlyAtCap_ReturnsTrue() {
        #expect(FreeTierLimits.restoreFits(recipes: FreeTierLimits.recipeCap, isPro: false))
    }

    @Test func restoreFits_OneRecipeOver_ReturnsFalse() {
        #expect(!FreeTierLimits.restoreFits(recipes: FreeTierLimits.recipeCap + 1, isPro: false))
    }

    @Test func restoreFits_Pro_AlwaysFits() {
        #expect(FreeTierLimits.restoreFits(recipes: 500, isPro: true))
    }

    // MARK: Counting a backup

    @Test func restoreFits_BackupWithManyCustomIngredientsAndRecipesAtCap_ReturnsTrue() throws {
        let backup = try makeBackup(recipes: FreeTierLimits.recipeCap, custom: 8)
        #expect(FreeTierLimits.restoreFits(backup, isPro: false))
    }

    @Test func restoreFits_BackupWithManyCustomIngredientsAndNoRecipes_ReturnsTrue() throws {
        let backup = try makeBackup(custom: FreeTierLimits.recipeCap + 5)
        #expect(FreeTierLimits.restoreFits(backup, isPro: false))
    }

    @Test func restoreFits_BackupOverRecipeCapWithCustomIngredients_ReturnsFalse() throws {
        let backup = try makeBackup(recipes: FreeTierLimits.recipeCap + 1, custom: 8)
        #expect(!FreeTierLimits.restoreFits(backup, isPro: false))
        #expect(FreeTierLimits.restoreFits(backup, isPro: true))
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
        let backup = try makeBackup(recipes: FreeTierLimits.recipeCap + 1)
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let coordinator = makeCoordinator()
        await restore(backup, with: coordinator, into: ctx, isPro: false)

        #expect(coordinator.pendingImport == nil)
        #expect(coordinator.generation == 0)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.name) == ["Olive Oil"])
    }

    @Test func stage_ManyCustomIngredientsWithinRecipeCapForFreeUser_Stages() throws {
        let backup = try makeBackup(recipes: FreeTierLimits.recipeCap, custom: 8)
        let coordinator = makeCoordinator()

        #expect(coordinator.stage(backup, isPro: false))
        #expect(coordinator.pendingImport != nil)
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
