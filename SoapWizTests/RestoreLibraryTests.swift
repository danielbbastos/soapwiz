import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// A restored store has to look the way a launch would leave it: every library
/// ingredient present, and nothing the backup already carried installed twice.
@Suite("Restore – ingredient library", .serialized)
@MainActor
struct RestoreLibraryTests: RestoreTestCase {

    @Test func perform_BackupWrittenBeforeTheLibrary_InstallsTheLibraryAndAdoptsMatches() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedStore(ctx, ingredientName: "Olive Oil")
        let coordinator = makeCoordinator()
        coordinator.ingredientLibrary = IngredientLibrary(entries: [
            .mock(slug: "olive-oil", name: "Olive Oil"),
            .mock(slug: "coconut-oil", name: "Coconut Oil")
        ])

        await restore(try BackupService.makeBackup(from: ctx), with: coordinator, into: ctx)
        defer { removeIfPresent(coordinator.rollbackFile) }

        let ingredients = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(ingredients.count == 2)
        #expect(Set(ingredients.map(\.librarySlug)) == ["olive-oil", "coconut-oil"])
    }

    @Test func perform_BackupWithLibraryState_KeepsItWithoutInstallingTwice() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let library = IngredientLibrary(entries: [.mock(slug: "olive-oil", name: "Olive Oil")])
        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)
        let olive = try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first)
        olive.isHidden = true
        try ctx.save()
        let coordinator = makeCoordinator()
        coordinator.ingredientLibrary = library

        await restore(try BackupService.makeBackup(from: ctx), with: coordinator, into: ctx)
        defer { removeIfPresent(coordinator.rollbackFile) }

        let restored = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(restored.count == 1)
        #expect(restored.first?.librarySlug == "olive-oil")
        #expect(restored.first?.isHidden == true)
    }
}
