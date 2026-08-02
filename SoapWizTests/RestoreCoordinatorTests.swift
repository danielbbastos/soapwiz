import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import SoapWiz

/// A restore wipes the store while the interface is still holding the models it is
/// about to delete. The coordinator's job is to take that interface down first and
/// rebuild it afterwards, whichever way the import goes.
@Suite("Restore coordinator", .serialized)
@MainActor
struct RestoreCoordinatorTests: RestoreTestCase {

    // MARK: - Tearing the interface down

    /// The tab-local navigation paths die with the views that own them, but
    /// `AppNavigation` outlives the rebuild — anything it still holds would be a
    /// deleted model the moment the wipe lands.
    @Test func begin_ClearsTheNavigationStateThatSurvivesTheRebuild() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let batch = Batch(recipe: nil, recipeName: "Castile", batchCount: 1)
        ctx.insert(batch)
        let ingredient = try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first)
        try ctx.save()

        let navigation = AppNavigation()
        navigation.historyPath = NavigationPath([batch])
        navigation.pendingRecipeSeed = RecipeSeed(ingredients: [ingredient])

        let coordinator = makeCoordinator()
        coordinator.stage(try BackupService.makeBackup(from: ctx))
        coordinator.begin(navigation: navigation)

        #expect(navigation.historyPath.isEmpty)
        #expect(navigation.pendingRecipeSeed == nil)
    }

    @Test func begin_MovesToTheRestoringPhase() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let coordinator = makeCoordinator()
        coordinator.stage(try BackupService.makeBackup(from: ctx))
        coordinator.begin(navigation: AppNavigation())

        #expect(coordinator.phase == .restoring)
        #expect(coordinator.pendingImport == nil)
    }

    // MARK: - Rebuilding it again

    /// Whichever way the restore goes, the interface has to come back — a failed
    /// import must not strand the user on the restoring placeholder.
    @Test func perform_OnSuccess_RebuildsTheInterface() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let coordinator = makeCoordinator()
        await restore(try BackupService.makeBackup(from: ctx), with: coordinator, into: ctx)
        defer { removeIfPresent(coordinator.rollbackFile) }

        #expect(coordinator.phase == .idle)
        #expect(coordinator.generation == 1)
    }

    @Test func perform_WhenRollbackCannotBeWritten_StillRebuildsTheInterface() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let coordinator = makeCoordinator()
        coordinator.rollbackDirectory = try makeUnwritableDirectory()
        await restore(try BackupService.makeBackup(from: ctx), with: coordinator, into: ctx)

        #expect(coordinator.phase == .idle)
        #expect(coordinator.generation == 1)
    }

    /// The placeholder's `.task` can fire again as the view comes and goes; a
    /// restore that was never confirmed must not run off the back of it.
    @Test func perform_WithoutBegin_DoesNothing() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let coordinator = makeCoordinator()
        coordinator.stage(try BackupService.makeBackup(from: ctx))
        await coordinator.perform(in: ctx)

        #expect(coordinator.generation == 0)
        #expect(coordinator.rollbackFile == nil)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.name) == ["Olive Oil"])
    }
}
