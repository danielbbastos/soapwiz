import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Restoring a backup wipes the store, and the confirmation dialog is the only
/// thing standing between a mis-tap and total data loss. A rollback file written
/// just before the wipe is what makes that recoverable.
@Suite("Rollback backup", .serialized)
@MainActor
struct RollbackBackupTests: RestoreTestCase {

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

        let coordinator = makeCoordinator()
        coordinator.rollbackDirectory = try makeUnwritableDirectory()
        await restore(try BackupService.makeBackup(from: otherCtx), with: coordinator, into: ctx)

        #expect(coordinator.errorMessage != nil)
        #expect(coordinator.rollbackFile == nil)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.name) == ["Olive Oil"])
    }

    // MARK: - Keeping Documents tidy

    /// One import's worth of undo is the whole promise. Without pruning, every
    /// confirmed import would leave another full-store snapshot in Documents.
    @Test func restore_AfterAnEarlierImport_LeavesOnlyTheNewestRollback() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let directory = try makeRollbackDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let stale = directory.appendingPathComponent("SoapWiz-Rollback-2020-01-01-000000.json")
        try Data("{}".utf8).write(to: stale)

        let coordinator = makeCoordinator()
        coordinator.rollbackDirectory = directory
        await restore(try BackupService.makeBackup(from: ctx), with: coordinator, into: ctx)

        let file = try #require(coordinator.rollbackFile)
        #expect(FileManager.default.fileExists(atPath: file.url.path))
        #expect(FileManager.default.fileExists(atPath: stale.path) == false)
        #expect(try rollbackFiles(in: directory) == [file.url.lastPathComponent])
    }

    /// A restore over an empty store writes no rollback, so there is nothing newer
    /// to replace the earlier ones with — they are still the only way back to data
    /// that nothing has overwritten.
    @Test func restore_OverEmptyStore_KeepsEarlierRollbacks() async throws {
        let (container, ctx) = try makeContext()
        _ = container

        let (otherContainer, otherCtx) = try makeContext()
        _ = otherContainer
        seedStore(otherCtx, ingredientName: "Coconut Oil")

        let directory = try makeRollbackDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let earlier = directory.appendingPathComponent("SoapWiz-Rollback-2020-01-01-000000.json")
        try Data("{}".utf8).write(to: earlier)

        let coordinator = makeCoordinator()
        coordinator.rollbackDirectory = directory
        await restore(try BackupService.makeBackup(from: otherCtx), with: coordinator, into: ctx)

        #expect(coordinator.rollbackFile == nil)
        #expect(coordinator.errorMessage == nil)
        #expect(FileManager.default.fileExists(atPath: earlier.path))
    }

    /// A failed restore rolls the context back, so its snapshot describes a store
    /// that was never replaced — and the user is never told the file exists.
    @Test func restore_WhenTheImportFails_LeavesNoOrphanedRollback() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let directory = try makeRollbackDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var incoming = try BackupService.makeBackup(from: ctx)
        incoming.version = BackupData.currentVersion + 1

        let coordinator = makeCoordinator()
        coordinator.rollbackDirectory = directory
        await restore(incoming, with: coordinator, into: ctx)

        #expect(coordinator.errorMessage != nil)
        #expect(coordinator.rollbackFile == nil)
        #expect(try rollbackFiles(in: directory).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.name) == ["Olive Oil"])
    }

    /// Pruning happens only after a restore succeeds. A snapshot the user still has
    /// must not be traded for one they might not get.
    @Test func restore_WhenRollbackCannotBeWritten_KeepsTheEarlierRollback() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let directory = try makeRollbackDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let earlier = directory.appendingPathComponent("SoapWiz-Rollback-2020-01-01-000000.json")
        try Data("{}".utf8).write(to: earlier)

        let coordinator = makeCoordinator()
        coordinator.rollbackDirectory = try makeUnwritableDirectory(in: directory)
        await restore(try BackupService.makeBackup(from: ctx), with: coordinator, into: ctx)

        #expect(coordinator.errorMessage != nil)
        #expect(FileManager.default.fileExists(atPath: earlier.path))
    }

    /// Pruning must not reach past its own files — an export saved alongside a
    /// rollback is the user's, not ours to delete.
    @Test func restore_Pruning_LeavesUnrelatedFilesAlone() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let directory = try makeRollbackDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let export = directory.appendingPathComponent("SoapWiz-Backup-2020-01-01-000000.json")
        try Data("{}".utf8).write(to: export)
        let unrelated = directory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: unrelated)

        let coordinator = makeCoordinator()
        coordinator.rollbackDirectory = directory
        await restore(try BackupService.makeBackup(from: ctx), with: coordinator, into: ctx)

        #expect(FileManager.default.fileExists(atPath: export.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
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
