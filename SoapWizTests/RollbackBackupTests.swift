import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import SoapWiz

/// Restoring a backup wipes the store, and the confirmation dialog is the only
/// thing standing between a mis-tap and total data loss. A rollback file written
/// just before the wipe is what makes that recoverable.
@Suite("Rollback backup", .serialized)
@MainActor
struct RollbackBackupTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    private func seedStore(_ ctx: ModelContext, ingredientName: String) {
        let category = IngredientCategory(name: "Oils")
        ctx.insert(category)
        let ingredient = Ingredient(name: ingredientName, category: category, unit: "g")
        ctx.insert(ingredient)
        try? ctx.save()
    }

    /// The settle delay exists to let UIKit finish deallocating the torn-down
    /// interface; with no interface there is nothing to wait for.
    private func makeCoordinator() -> RestoreCoordinator {
        let coordinator = RestoreCoordinator()
        coordinator.settleDelay = .zero
        return coordinator
    }

    /// Stages and runs a restore the way the interface does: confirm, tear down, perform.
    private func restore(
        _ backup: BackupData,
        with coordinator: RestoreCoordinator,
        into ctx: ModelContext
    ) async {
        coordinator.stage(backup)
        coordinator.begin(navigation: AppNavigation())
        await coordinator.perform(in: ctx)
    }

    private func removeIfPresent(_ file: ExportFile?) {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file.url)
    }

    // MARK: - When a rollback is written

    @Test func restore_OverPopulatedStore_WritesRollbackFile() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let coordinator = makeCoordinator()
        await restore(try BackupService.makeBackup(from: ctx), with: coordinator, into: ctx)
        defer { removeIfPresent(coordinator.rollbackFile) }

        let file = try #require(coordinator.rollbackFile)
        #expect(FileManager.default.fileExists(atPath: file.url.path))
        #expect(file.url.lastPathComponent.hasPrefix("SoapWiz-Rollback-"))
        #expect(coordinator.errorMessage == nil)
    }

    /// The point of the file: restoring it has to put the store back.
    @Test func rollbackFile_RestoresThePreImportStore() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        // Import a different store over the top.
        let (otherContainer, otherCtx) = try makeContext()
        _ = otherContainer
        seedStore(otherCtx, ingredientName: "Coconut Oil")
        let incoming = try BackupService.makeBackup(from: otherCtx)

        let coordinator = makeCoordinator()
        await restore(incoming, with: coordinator, into: ctx)
        let file = try #require(coordinator.rollbackFile)
        defer { removeIfPresent(file) }

        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.name) == ["Coconut Oil"])

        let rollback = try BackupService.decode(Data(contentsOf: file.url))
        try BackupService.restore(rollback, into: ctx)

        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.name) == ["Olive Oil"])
    }

    // MARK: - When no rollback is written

    @Test func restore_OverEmptyStore_WritesNoRollbackFile() async throws {
        let (container, ctx) = try makeContext()
        _ = container

        let (otherContainer, otherCtx) = try makeContext()
        _ = otherContainer
        seedStore(otherCtx, ingredientName: "Coconut Oil")

        let coordinator = makeCoordinator()
        await restore(try BackupService.makeBackup(from: otherCtx), with: coordinator, into: ctx)
        defer { removeIfPresent(coordinator.rollbackFile) }

        #expect(coordinator.rollbackFile == nil)
        #expect(coordinator.errorMessage == nil)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).count == 1)
    }

    /// `AppSettings` alone is not worth a rollback file — `resolve` inserts one on
    /// every launch, so treating it as data would mean every import wrote a file
    /// containing nothing the user would miss.
    @Test func isEmpty_SettingsOnlyStore_IsStillEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        _ = AppSettings.resolve(in: ctx)
        try ctx.save()

        let backup = try BackupService.makeBackup(from: ctx)

        #expect(backup.isEmpty)
    }

    @Test func isEmpty_StoreWithAnyEntity_IsNotEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        #expect(try BackupService.makeBackup(from: ctx).isEmpty == false)
    }

    // MARK: - Failing closed

    /// A restore that cannot write its rollback must change nothing. Restoring
    /// anyway would remove the guarantee at the exact moment the user needs it.
    @Test func restore_WhenRollbackCannotBeWritten_LeavesTheStoreUntouched() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let (otherContainer, otherCtx) = try makeContext()
        _ = otherContainer
        seedStore(otherCtx, ingredientName: "Coconut Oil")

        // A path nested inside a regular file can never be written to.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollback-blocker-\(UUID().uuidString)")
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        let coordinator = makeCoordinator()
        coordinator.rollbackDirectory = blocker.appendingPathComponent("nested")
        await restore(try BackupService.makeBackup(from: otherCtx), with: coordinator, into: ctx)

        #expect(coordinator.errorMessage != nil)
        #expect(coordinator.rollbackFile == nil)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.name) == ["Olive Oil"])
    }

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

        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollback-blocker-\(UUID().uuidString)")
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        let coordinator = makeCoordinator()
        coordinator.rollbackDirectory = blocker.appendingPathComponent("nested")
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

    // MARK: - Naming

    @Test func rollbackFileName_IsDistinctFromAnExportAndLocaleIndependent() {
        let date = try? #require(
            DateComponents(
                calendar: Calendar(identifier: .gregorian),
                timeZone: TimeZone(identifier: "UTC"),
                year: 2026, month: 6, day: 25, hour: 14, minute: 30, second: 0
            ).date
        )
        guard let date else { return }

        let rollback = RestoreCoordinator.rollbackFileName(for: date)
        let export = DataTransferViewModel.fileName(for: date)

        #expect(rollback.hasPrefix("SoapWiz-Rollback-"))
        #expect(rollback.hasSuffix(".json"))
        #expect(rollback != export)
    }
}
