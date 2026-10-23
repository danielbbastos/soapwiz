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

    /// One entry per pooled ingredient, in payload order. The whole pool, not
    /// just what the ticked recipes use: an entry keeps its position and any
    /// match the user made while its recipes are unticked, so ticking them again
    /// finds both as they were.
    let ingredients: [RecipeTransferIngredientPlan]

    /// Collection names that matched something the recipient already has.
    /// Keyed by the name as written in the payload.
    let matchedCollections: [String: RecipeCollection]

    /// Every collection name with no match here, whichever recipes use it.
    private let allUnmatchedCollectionNames: [String]

    /// The incoming recipes, each with an identity of its own and the name it
    /// will actually be saved under. Every recipe in the payload, ticked or not,
    /// so the review screen can list them all.
    ///
    /// Identified by position rather than by name: nothing stops a file holding
    /// two recipes called "Bar", and on a screen whose entire job is to say what
    /// is about to be added, two rows collapsing into one would be the worst
    /// possible place to lose something.
    let recipeSummaries: [RecipeTransferRecipeSummary]

    /// The summary ids the user means to import. Transient review state, never
    /// stored: a file opened again starts with every recipe ticked.
    let selectedRecipeIDs: Set<Int>

    /// What `summaries` needs from the library to name and identify the ticked
    /// recipes again, kept so a change of selection doesn't have to ask the store.
    private let libraryNameKeys: Set<String>
    private let libraryRecipesByUUID: [UUID: Recipe]

    /// The recipes that will be imported, in payload order.
    var selectedRecipes: [RecipeTransferRecipeSummary] {
        recipeSummaries.filter { selectedRecipeIDs.contains($0.id) }
    }

    /// How many recipes will be imported, which is what the free tier counts.
    var recipeCount: Int { selectedRecipeIDs.count }

    var hasSelection: Bool { !selectedRecipeIDs.isEmpty }

    /// Whether there is a choice to make. A single recipe has nothing to tick.
    var isMultiRecipe: Bool { payload.recipes.count > 1 }

    func isSelected(_ id: Int) -> Bool { selectedRecipeIDs.contains(id) }

    /// The pooled ingredients the ticked recipes actually use. Only these are
    /// created; what an unticked recipe alone uses is left out.
    var neededIngredientIDs: Set<Int> {
        Set(selectedRecipes.flatMap { $0.recipe.ingredients.map(\.ingredientIndex) })
    }

    private var neededIngredients: [RecipeTransferIngredientPlan] {
        let needed = neededIngredientIDs
        return ingredients.filter { needed.contains($0.id) }
    }

    var ingredientsToCreate: [RecipeTransferIngredientPlan] {
        neededIngredients.filter(\.willBeCreated)
    }

    /// Matched ingredients whose stored chemistry differs from the sender's.
    ///
    /// Surfaced because the recipient's own values are the ones that will be
    /// used, and silently calculating a different lye weight than the sender saw
    /// is exactly the kind of surprise a caustic recipe must not spring.
    var conflictingIngredients: [RecipeTransferIngredientPlan] {
        neededIngredients.filter(\.hasChemistryConflict)
    }

    /// Collection names with no match here, among those the ticked recipes
    /// name. Those recipes arrive unfiled — filing is a personal decision, and
    /// an import must not litter a library with a stranger's folders.
    var unmatchedCollectionNames: [String] {
        let used = Set(selectedRecipes.flatMap { $0.recipe.collectionNames })
        return allUnmatchedCollectionNames.filter(used.contains)
    }

    /// Whether there is anything worth importing. An empty payload decodes fine
    /// and would otherwise present a review screen with nothing on it. About the
    /// file, not the selection: unticking everything is a state to show, not a
    /// failure to read.
    var isEmpty: Bool { payload.recipes.isEmpty }

    init(
        payload: RecipeTransferData,
        inventory: [Ingredient],
        collections: [RecipeCollection],
        recipes: [Recipe] = []
    ) {
        self.payload = payload
        libraryNameKeys = Set(recipes.map(\.name).map(\.lookupKey))
        libraryRecipesByUUID = Dictionary(recipes.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        selectedRecipeIDs = Set(payload.recipes.indices)
        recipeSummaries = Self.summaries(
            for: payload,
            selecting: selectedRecipeIDs,
            libraryNameKeys: libraryNameKeys,
            libraryRecipesByUUID: libraryRecipesByUUID
        )

        let index = Self.index(of: inventory)
        let slugIndex = Self.slugIndex(of: inventory)
        let roles = Self.rolesByIngredientIndex(in: payload)
        ingredients = payload.ingredients.enumerated().map { offset, incoming in
            // Slug first: it survives a rename on either device, and two rows
            // carrying one slug are two copies of the same curated entry. The name
            // remains the fallback, and the only path a payload without slugs has.
            let bySlug = incoming.librarySlug.flatMap { slug in
                slug.isEmpty ? nil : slugIndex[slug]
            }
            return RecipeTransferIngredientPlan(
                id: offset,
                incoming: incoming,
                role: roles[offset] ?? .additive,
                existing: bySlug ?? index[incoming.name.lookupKey],
                matchedBySlug: bySlug != nil
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
        allUnmatchedCollectionNames = unmatched
    }

    private init(
        payload: RecipeTransferData,
        ingredients: [RecipeTransferIngredientPlan],
        matchedCollections: [String: RecipeCollection],
        allUnmatchedCollectionNames: [String],
        recipeSummaries: [RecipeTransferRecipeSummary],
        selectedRecipeIDs: Set<Int>,
        libraryNameKeys: Set<String>,
        libraryRecipesByUUID: [UUID: Recipe]
    ) {
        self.payload = payload
        self.ingredients = ingredients
        self.matchedCollections = matchedCollections
        self.allUnmatchedCollectionNames = allUnmatchedCollectionNames
        self.recipeSummaries = recipeSummaries
        self.selectedRecipeIDs = selectedRecipeIDs
        self.libraryNameKeys = libraryNameKeys
        self.libraryRecipesByUUID = libraryRecipesByUUID
    }

    /// This plan importing only the recipes with these ids. Ids the payload
    /// doesn't have are ignored. Ingredients are carried over untouched; names
    /// and identities are worked out again over the ticked recipes alone, since
    /// a recipe that isn't coming can't have claimed a name or an identity
    /// first.
    func selecting(_ ids: Set<Int>) -> RecipeTransferPlan {
        let selected = ids.intersection(payload.recipes.indices)
        return RecipeTransferPlan(
            payload: payload,
            ingredients: ingredients,
            matchedCollections: matchedCollections,
            allUnmatchedCollectionNames: allUnmatchedCollectionNames,
            recipeSummaries: Self.summaries(
                for: payload,
                selecting: selected,
                libraryNameKeys: libraryNameKeys,
                libraryRecipesByUUID: libraryRecipesByUUID
            ),
            selectedRecipeIDs: selected,
            libraryNameKeys: libraryNameKeys,
            libraryRecipesByUUID: libraryRecipesByUUID
        )
    }

    /// Works out what each incoming recipe will be called, and whether the
    /// library has seen it before.
    ///
    /// Whether the library has seen it is answered by the payload's uuid, and
    /// only by the name when the payload carries none — a version-1 file, or one
    /// written by a build older than the field. The uuid is the stronger answer
    /// precisely where the name is the weakest: a recipe renamed on either
    /// device still matches, and two different recipes that happen to share a
    /// name no longer look like one recipe arriving twice. The naming rule below
    /// runs either way, since both recipes still have to be told apart in a list.
    ///
    /// Recognising a recipe does not currently change what happens to it. It is
    /// still added alongside the one already there, because replacing would put
    /// the sender's copy over the user's own edits and no screen has yet asked
    /// them whether that is what they want. What changes is what the review
    /// screen can honestly say about it.
    ///
    /// A name the library already uses gets the same "(copy)" suffix the
    /// Duplicate action produces, rather than a second convention invented for
    /// import. Two identical rows in the list is the outcome worth avoiding:
    /// the user has no way to tell which is theirs and which just arrived.
    ///
    /// Names claimed earlier in the same payload count as taken, so a file
    /// holding two recipes called "Bar" produces "Bar" and "Bar (copy)" rather
    /// than the pair it started with. Deliberately not applied to an untitled
    /// recipe: " (copy)" reads as nothing at all.
    ///
    /// Only the selected recipes claim names and identities, in payload order:
    /// with the first of two "Bar"s unticked, the second is the only one coming
    /// and keeps its name. An unselected recipe is resolved as if it were the
    /// next to arrive, claiming nothing, so its summary is never missing a name.
    private static func summaries(
        for payload: RecipeTransferData,
        selecting selected: Set<Int>,
        libraryNameKeys: Set<String>,
        libraryRecipesByUUID byUUID: [UUID: Recipe]
    ) -> [RecipeTransferRecipeSummary] {
        var taken = libraryNameKeys
        var claimed = Set(byUUID.keys)
        return payload.recipes.enumerated().map { offset, recipe in
            let incoming = recipe.name.trimmingCharacters(in: .whitespaces)
            let resolved: String
            if incoming.isEmpty || !taken.contains(incoming.lookupKey) {
                resolved = incoming
            } else {
                resolved = RecipeDuplicator.copyName(of: incoming, taken: taken)
            }
            let identity = Self.identity(for: recipe, claimed: claimed)
            if selected.contains(offset) {
                if !resolved.isEmpty { taken.insert(resolved.lookupKey) }
                claimed.insert(identity)
            }
            return RecipeTransferRecipeSummary(
                id: offset,
                recipe: recipe,
                resolvedName: resolved,
                resolvedUUID: identity,
                knownRecipe: recipe.uuid.flatMap { byUUID[$0] }
            )
        }
    }

    /// The identity the imported recipe will be saved under.
    ///
    /// The sender's, when the library does not already hold it. That is what
    /// makes the identity worth carrying at all: a recipe that travels keeps
    /// being the same recipe, so the friend who improves it and sends it back is
    /// recognisably returning *this* recipe rather than offering a new one.
    ///
    /// Fresh in every other case — the library already has that identity, the
    /// payload claimed it for an earlier recipe in the same file, or it carried
    /// none. Import adds a row rather than replacing one, and two rows sharing
    /// an identity is the one state the format cannot describe: a later payload
    /// would match both and neither answer would be right.
    private static func identity(for recipe: RecipeTransferRecipe, claimed: Set<UUID>) -> UUID {
        guard let incoming = recipe.uuid, !claimed.contains(incoming) else { return UUID() }
        return incoming
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

    /// Inventory keyed by library slug, with the same tie-break as `index(of:)` and
    /// for the same reason: until the merge collapses them, two rows can carry one
    /// slug, and the useful one is the one a recipe can be calculated from.
    private static func slugIndex(of inventory: [Ingredient]) -> [String: Ingredient] {
        var index: [String: Ingredient] = [:]
        for ingredient in inventory {
            let slug = ingredient.librarySlug
            guard !slug.isEmpty else { continue }
            guard let existing = index[slug] else {
                index[slug] = ingredient
                continue
            }
            if existing.sapValue == nil, ingredient.sapValue != nil {
                index[slug] = ingredient
            }
        }
        return index
    }
}
