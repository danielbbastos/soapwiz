import Foundation
import SwiftData

/// One bundled starter recipe as the library shows it: its place in the
/// payload, and a throwaway `Recipe` to read it from.
struct StarterRecipePreview: Identifiable {
    let index: Int
    let recipe: Recipe

    var id: Int { index }
}

/// The starter recipes, built as real recipes in a container of their own.
///
/// The container is in memory, has no CloudKit mirror and is never saved, so a
/// starter recipe can't reach the user's store, sync, backups or the free-tier
/// count by being looked at. Only `copy` writes anything to the user's store,
/// and it does so from the payload, not from these previews. The container is
/// kept for as long as the library is, since its recipes die with it.
final class StarterRecipeLibrary {
    let previews: [StarterRecipePreview]

    private let payload: RecipeTransferData
    private let container: ModelContainer

    init(bundle: Bundle = .main) throws {
        let payload = try StarterRecipes.payload(in: bundle)
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        let plan = RecipeTransferPlan(payload: payload, inventory: [], collections: [])
        let recipes = RecipeTransferImporter.apply(plan, into: context, categories: [])

        self.payload = payload
        self.container = container
        previews = recipes.enumerated().map { StarterRecipePreview(index: $0.offset, recipe: $0.element) }
    }

    /// Whether the user's recipes already include this starter, by identity: a
    /// copy keeps the starter's `uuid` unless the user already holds it.
    func isInYourRecipes(_ preview: StarterRecipePreview, among recipes: [Recipe]) -> Bool {
        recipes.contains { $0.uuid == preview.recipe.uuid }
    }

    /// Copies one starter into the user's store and saves it, or returns `nil`
    /// with the store rolled back when the save fails.
    ///
    /// Planned against the user's own ingredients, so the starter's oils match
    /// the library rows already installed and none are created. A name or
    /// identity the user already holds is renamed or reissued by the plan, so
    /// the same starter can be copied again.
    func copy(
        _ preview: StarterRecipePreview,
        inventory: [Ingredient],
        collections: [RecipeCollection],
        recipes: [Recipe],
        categories: [IngredientCategory],
        into context: ModelContext
    ) -> Recipe? {
        let plan = RecipeTransferPlan(
            payload: payload,
            inventory: inventory,
            collections: collections,
            recipes: recipes
        )
        .selecting([preview.index])
        let created = RecipeTransferImporter.apply(plan, into: context, categories: categories)
        do {
            try context.save()
            return created.first
        } catch {
            context.rollback()
            return nil
        }
    }
}
