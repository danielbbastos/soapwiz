import Testing
import Foundation
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

    private func removeIfPresent(_ file: DataTransferViewModel.ExportFile?) {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file.url)
    }

    // MARK: - When a rollback is written

    @Test func confirmImport_OverPopulatedStore_WritesRollbackFile() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        let model = DataTransferViewModel()
        model.pendingImport = try BackupService.makeBackup(from: ctx)
        model.confirmImport(into: ctx)
        defer { removeIfPresent(model.rollbackFile) }

        let file = try #require(model.rollbackFile)
        #expect(FileManager.default.fileExists(atPath: file.url.path))
        #expect(file.url.lastPathComponent.hasPrefix("SoapWiz-Rollback-"))
        #expect(model.errorMessage == nil)
    }

    /// The point of the file: restoring it has to put the store back.
    @Test func rollbackFile_RestoresThePreImportStore() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")

        // Import a different store over the top.
        let (otherContainer, otherCtx) = try makeContext()
        _ = otherContainer
        seedStore(otherCtx, ingredientName: "Coconut Oil")
        let incoming = try BackupService.makeBackup(from: otherCtx)

        let model = DataTransferViewModel()
        model.pendingImport = incoming
        model.confirmImport(into: ctx)
        let file = try #require(model.rollbackFile)
        defer { removeIfPresent(file) }

        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.name) == ["Coconut Oil"])

        let rollback = try BackupService.decode(Data(contentsOf: file.url))
        try BackupService.restore(rollback, into: ctx)

        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.name) == ["Olive Oil"])
    }

    // MARK: - When no rollback is written

    @Test func confirmImport_OverEmptyStore_WritesNoRollbackFile() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let (otherContainer, otherCtx) = try makeContext()
        _ = otherContainer
        seedStore(otherCtx, ingredientName: "Coconut Oil")

        let model = DataTransferViewModel()
        model.pendingImport = try BackupService.makeBackup(from: otherCtx)
        model.confirmImport(into: ctx)
        defer { removeIfPresent(model.rollbackFile) }

        #expect(model.rollbackFile == nil)
        #expect(model.errorMessage == nil)
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

        let rollback = DataTransferViewModel.rollbackFileName(for: date)
        let export = DataTransferViewModel.fileName(for: date)

        #expect(rollback.hasPrefix("SoapWiz-Rollback-"))
        #expect(rollback.hasSuffix(".json"))
        #expect(rollback != export)
    }
}
