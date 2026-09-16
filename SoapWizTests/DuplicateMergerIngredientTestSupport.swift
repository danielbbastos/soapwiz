import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Shared container and catalog fixtures for the ingredient duplicate-merge
/// suites, so the slug-pass tests and the left-alone tests build their rows the
/// same way rather than keeping two copies that can drift.
@MainActor
protocol DuplicateMergerIngredientHelpers {}

extension DuplicateMergerIngredientHelpers {
    var olive: IngredientLibraryEntry {
        IngredientLibraryEntry.mock(
            slug: "olive-oil",
            name: "Olive Oil",
            aliases: ["Extra Virgin Olive Oil", "EVOO"]
        )
    }

    var coconut: IngredientLibraryEntry {
        IngredientLibraryEntry.mock(
            slug: "coconut-oil",
            name: "Coconut Oil",
            sapValue: 0.183,
            kohSapValue: 0.257,
            density: 0.921,
            fattyAcidProfile: FattyAcidProfile(lauric: 48, myristic: 19, palmitic: 9, stearic: 3, oleic: 8, linoleic: 2)
        )
    }

    func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    func uuid(_ index: Int) throws -> UUID {
        try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)"))
    }

    /// A row as the installer leaves it: the entry's name, unit and chemistry,
    /// carrying its slug.
    func installed(_ entry: IngredientLibraryEntry, _ index: Int) throws -> Ingredient {
        let ingredient = Ingredient.mock(matching: entry)
        ingredient.librarySlug = entry.slug
        ingredient.uuid = try uuid(index)
        return ingredient
    }

    func ingredients(_ ctx: ModelContext) throws -> [Ingredient] {
        try ctx.fetch(FetchDescriptor<Ingredient>())
    }
}
