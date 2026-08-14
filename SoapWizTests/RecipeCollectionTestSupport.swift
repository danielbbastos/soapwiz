import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Shared container and fixtures for the recipe-collection suites.
@MainActor
protocol RecipeCollectionTestHelpers {}

extension RecipeCollectionTestHelpers {
    func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    /// Three filed recipes — one under Christmas, one under Gifts, one under
    /// both — plus one left unfiled.
    func seedCollections(_ ctx: ModelContext) throws -> CollectionFixture {
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(christmas)
        ctx.insert(gifts)

        let cinnamon = Recipe(name: "Cinnamon Bar")
        let lavender = Recipe(name: "Lavender Bar")
        let both = Recipe(name: "Spiced Gift Bar")
        let plain = Recipe(name: "Castile")
        for recipe in [cinnamon, lavender, both, plain] {
            ctx.insert(recipe)
        }
        cinnamon.collections = [christmas]
        lavender.collections = [gifts]
        both.collections = [christmas, gifts]
        try ctx.save()

        return CollectionFixture(christmas: christmas, gifts: gifts, recipes: [cinnamon, lavender, both, plain])
    }
}

/// The seeded graph, as a named type rather than a tuple so the members stay
/// readable at the call site as the fixture grows.
@MainActor
struct CollectionFixture {
    let christmas: RecipeCollection
    let gifts: RecipeCollection
    let recipes: [Recipe]

    func recipe(named name: String) throws -> Recipe {
        try #require(recipes.first { $0.name == name })
    }
}
