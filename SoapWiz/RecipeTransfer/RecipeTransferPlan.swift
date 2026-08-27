import Foundation
import SwiftData

/// What importing a payload would do, worked out before anything is written.
///
/// Built so the review screen can show the consequences and the importer can
/// apply them without deciding anything for itself. The two must agree: a screen
/// that describes one outcome and an importer that produces another is worse
/// than no screen at all.
@MainActor
struct RecipeTransferPlan {
    let payload: RecipeTransferData

    /// One entry per pooled ingredient, in payload order.
    let ingredients: [RecipeTransferIngredientPlan]

    /// Collection names that matched something the recipient already has.
    /// Keyed by the name as written in the payload.
    let matchedCollections: [String: RecipeCollection]

    /// Collection names with no match here. The recipes that named them arrive
    /// unfiled — filing is a personal decision, and an import must not litter a
    /// library with a stranger's folders.
    let unmatchedCollectionNames: [String]

    var recipeCount: Int { payload.recipes.count }

    /// The incoming recipes, each with an identity of its own.
    ///
    /// Identified by position rather than by name: nothing stops a file holding
    /// two recipes called "Bar", and on a screen whose entire job is to say what
    /// is about to be added, two rows collapsing into one would be the worst
    /// possible place to lose something.
    var recipeSummaries: [RecipeTransferRecipeSummary] {
        payload.recipes.enumerated().map(RecipeTransferRecipeSummary.init)
    }

    var ingredientsToCreate: [RecipeTransferIngredientPlan] {
        ingredients.filter(\.willBeCreated)
    }

    var matchedIngredients: [RecipeTransferIngredientPlan] {
        ingredients.filter { !$0.willBeCreated }
    }

    /// Matched ingredients whose stored chemistry differs from the sender's.
    ///
    /// Surfaced because the recipient's own values are the ones that will be
    /// used, and silently calculating a different lye weight than the sender saw
    /// is exactly the kind of surprise a caustic recipe must not spring.
    var conflictingIngredients: [RecipeTransferIngredientPlan] {
        ingredients.filter(\.hasChemistryConflict)
    }

    /// Whether there is anything worth importing. An empty payload decodes fine
    /// and would otherwise present a review screen with nothing on it.
    var isEmpty: Bool { payload.recipes.isEmpty }

    init(payload: RecipeTransferData, inventory: [Ingredient], collections: [RecipeCollection]) {
        self.payload = payload

        let index = Self.index(of: inventory)
        let roles = Self.rolesByIngredientIndex(in: payload)
        ingredients = payload.ingredients.enumerated().map { offset, incoming in
            RecipeTransferIngredientPlan(
                id: offset,
                incoming: incoming,
                role: roles[offset] ?? .additive,
                existing: index[incoming.name.lookupKey]
            )
        }

        var matched: [String: RecipeCollection] = [:]
        var unmatched: [String] = []
        let collectionIndex = Dictionary(
            collections.map { ($0.name.lookupKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for name in Set(payload.recipes.flatMap(\.collectionNames)).sorted() {
            if let collection = collectionIndex[name.lookupKey] {
                matched[name] = collection
            } else {
                unmatched.append(name)
            }
        }
        matchedCollections = matched
        unmatchedCollectionNames = unmatched
    }

    /// The role each pooled ingredient is used in, taken from the first line
    /// item that references it.
    ///
    /// Only used to pick a category for an ingredient about to be created, so
    /// the first use is a good enough answer: an ingredient used as an oil in
    /// one recipe and an additive in another is the same substance either way,
    /// and the category is a filing decision the user can change.
    private static func rolesByIngredientIndex(in payload: RecipeTransferData) -> [Int: RecipeIngredientRole] {
        var roles: [Int: RecipeIngredientRole] = [:]
        for recipe in payload.recipes {
            for line in recipe.ingredients where roles[line.ingredientIndex] == nil {
                roles[line.ingredientIndex] = RecipeIngredientRole(rawValue: line.role) ?? .additive
            }
        }
        return roles
    }

    /// Inventory keyed by lookup key, preferring the copy that carries a
    /// saponification value — the same tie-break `RecipeIngredientReconciler`
    /// makes, and for the same reason: two rows can share a name while CloudKit
    /// is still collapsing a duplicate, and the useful one is the one a recipe
    /// can be calculated from.
    private static func index(of inventory: [Ingredient]) -> [String: Ingredient] {
        var index: [String: Ingredient] = [:]
        for ingredient in inventory {
            let key = ingredient.name.lookupKey
            guard !key.isEmpty else { continue }
            guard let existing = index[key] else {
                index[key] = ingredient
                continue
            }
            if existing.sapValue == nil, ingredient.sapValue != nil {
                index[key] = ingredient
            }
        }
        return index
    }
}

/// One incoming recipe, as the review screen lists it.
struct RecipeTransferRecipeSummary: Identifiable {
    let id: Int
    let recipe: RecipeTransferRecipe

    init(id: Int, recipe: RecipeTransferRecipe) {
        self.id = id
        self.recipe = recipe
    }

    var displayName: String {
        recipe.name.isEmpty ? "Untitled Recipe" : recipe.name
    }

    /// Kind and size, so a list of fifteen is scannable and a non-soap recipe
    /// is recognisable as one before it is imported.
    var detail: String {
        let kind = recipe.kind == .soap ? "Soap" : "Non-soap"
        let count = recipe.ingredients.count
        return "\(kind) · \(count) \(count == 1 ? "ingredient" : "ingredients")"
    }
}

/// One incoming ingredient and what will become of it.
@MainActor
struct RecipeTransferIngredientPlan: Identifiable {
    /// Position in the payload's ingredient pool.
    ///
    /// Identity by position rather than by name, because the pool is built by
    /// model identity on the sending side: two rows sharing a name — a CloudKit
    /// duplicate the sender hasn't merged yet — are two separate entries here,
    /// and keying on the name would collapse them in every `ForEach`.
    let id: Int

    let incoming: RecipeTransferIngredient

    /// The role its first line item uses it in, which decides the category a
    /// created ingredient is filed under.
    let role: RecipeIngredientRole

    /// The inventory ingredient it matched, or `nil` when it will be created.
    let existing: Ingredient?

    var name: String { incoming.name }

    var willBeCreated: Bool { existing == nil }

    /// The category a created ingredient is filed under, by name.
    var suggestedCategoryName: String {
        switch role {
        case .oil: IngredientCategory.Name.oils
        case .fragrance: IngredientCategory.Name.fragrances
        case .additive: IngredientCategory.Name.additives
        }
    }

    /// Whether the recipient already has this ingredient with different
    /// chemistry from the sender's.
    ///
    /// Compared only on the values that change a calculation. A different
    /// fatty-acid profile moves the soap-property stats but not the lye weight,
    /// and is included for the same reason: the recipe will not read the way it
    /// read on the sender's device, and the user should hear that from the app
    /// rather than notice it later.
    var hasChemistryConflict: Bool {
        guard let existing else { return false }
        return existing.sapValue != incoming.sapValue
            || existing.kohSapValue != incoming.kohSapValue
            || existing.density != incoming.density
            || existing.fattyAcidProfile != incoming.fattyAcidProfile
    }
}
