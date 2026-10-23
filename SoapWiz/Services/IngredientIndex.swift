import Foundation

/// The inventory keyed two ways, for the importers that match incoming names
/// against it: by `String.lookupKey` of the name, and by library slug.
///
/// Two ingredients can share a name or a slug while CloudKit is still collapsing
/// a duplicate, so a tie is broken on usefulness rather than on arrival order:
/// the copy that carries a saponification value is the one a recipe can actually
/// be costed and calculated from. Rows with an empty key — a blank name, or no
/// slug because the user created the ingredient — are left out, so they can
/// never match each other.
struct IngredientIndex {
    private let byName: [String: Ingredient]
    private let bySlug: [String: Ingredient]

    init(_ inventory: [Ingredient]) {
        byName = Self.index(inventory, keyOf: { $0.name.lookupKey })
        bySlug = Self.index(inventory, keyOf: { $0.librarySlug })
    }

    /// The ingredient whose name folds to the same lookup key as `name`.
    func ingredient(named name: String) -> Ingredient? {
        byName[name.lookupKey]
    }

    /// The ingredient installed from, or adopted by, the library entry `slug`.
    func ingredient(slug: String) -> Ingredient? {
        bySlug[slug]
    }

    private static func index(_ inventory: [Ingredient], keyOf: (Ingredient) -> String) -> [String: Ingredient] {
        var index: [String: Ingredient] = [:]
        for ingredient in inventory {
            let key = keyOf(ingredient)
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
