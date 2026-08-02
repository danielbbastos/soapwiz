import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import SoapWiz

/// Shared setup for the restore suites. They are split across files by subject —
/// the rollback file's guarantees in one, the coordinator's lifecycle in the other —
/// and both need the same store, coordinator and scratch directories.
@MainActor
protocol RestoreTestCase {}

@MainActor
extension RestoreTestCase {

    func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    func seedStore(_ ctx: ModelContext, ingredientName: String) {
        let category = IngredientCategory(name: "Oils")
        ctx.insert(category)
        let ingredient = Ingredient(name: ingredientName, category: category, unit: "g")
        ctx.insert(ingredient)
        try? ctx.save()
    }

    /// The settle delay exists to let UIKit finish deallocating the torn-down
    /// interface; with no interface there is nothing to wait for.
    func makeCoordinator() -> RestoreCoordinator {
        let coordinator = RestoreCoordinator()
        coordinator.settleDelay = .zero
        return coordinator
    }

    /// Stages and runs a restore the way the interface does: confirm, tear down, perform.
    func restore(
        _ backup: BackupData,
        with coordinator: RestoreCoordinator,
        into ctx: ModelContext
    ) async {
        coordinator.stage(backup)
        coordinator.begin(navigation: AppNavigation())
        await coordinator.perform(in: ctx)
    }

    /// An empty directory of its own, so a test sees only the files it put there.
    func makeRollbackDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollbacks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A directory path that can never be written to, because it is nested inside a
    /// regular file. Used to drive the fail-closed path.
    func makeUnwritableDirectory(in parent: URL? = nil) throws -> URL {
        let blocker = (parent ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("rollback-blocker-\(UUID().uuidString)")
        try Data().write(to: blocker)
        return blocker.appendingPathComponent("nested")
    }

    func rollbackFiles(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("SoapWiz-Rollback-") }
            .sorted()
    }

    func removeIfPresent(_ file: ExportFile?) {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file.url)
    }
}
