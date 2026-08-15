import Foundation
import SwiftData

/// A named theme a recipe can belong to ("Christmas", "Gifts", "Shampoo bars").
///
/// Membership is many-to-many rather than a single-parent folder: a recipe
/// genuinely belongs to several themes at once, and forcing a choice is a choice
/// the user would immediately want to undo. Recipes stay in the one flat list
/// and collections act as an overlay over it.
@Model
final class RecipeCollection {
    /// Stable identity across devices, so a name collision arriving from CloudKit
    /// can be collapsed the same way everywhere. See `DuplicateMerger`.
    var uuid: UUID = UUID()
    var name: String = ""

    /// Raw value of `CollectionColor`, or empty for the neutral chip.
    var colorName: String = ""

    /// Optional for CloudKit; read and write through `recipes`. Neither name is
    /// usable in `#Predicate` — see `ModelContainerFactory.schema`.
    ///
    /// `.nullify` on both sides: deleting a collection is a filing decision and
    /// must never take the recipes with it.
    @Relationship(deleteRule: .nullify, originalName: "recipes", inverse: \Recipe.collectionsStorage)
    var recipesStorage: [Recipe]? = []

    var recipes: [Recipe] {
        get { recipesStorage ?? [] }
        set { recipesStorage = newValue }
    }

    var color: CollectionColor { CollectionColor.resolve(colorName) }

    init(name: String, colorName: String = "") {
        self.name = name
        self.colorName = colorName
    }
}

extension Recipe {
    /// Whether this recipe is filed under `collection`. Compared by identity
    /// rather than equality: two rows can share a name while a CloudKit
    /// duplicate is still waiting for `DuplicateMerger` to collapse them.
    func isFiled(under collection: RecipeCollection) -> Bool {
        collections.contains { $0 === collection }
    }
}

extension Array where Element == RecipeCollection {
    /// Deterministic display order. The `uuid` tie-break matters while a CloudKit
    /// duplicate is still unmerged: two rows then share a name, and an unstable
    /// order would make the recipe form's dirty check fire on its own.
    var sortedByName: [RecipeCollection] {
        sorted { ($0.name.lookupKey, $0.uuid.uuidString) < ($1.name.lookupKey, $1.uuid.uuidString) }
    }
}

/// The accent a collection's chip is tinted with. A closed set rather than free
/// text so the stored value always resolves to something renderable, and so the
/// chips stay a palette instead of drifting into arbitrary colours.
enum CollectionColor: String, CaseIterable, Identifiable {
    case neutral = ""
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case purple
    case pink

    var id: Self { self }

    /// Resolves a stored raw value, defaulting to the neutral chip — an unknown
    /// colour arriving from a newer build must still render.
    static func resolve(_ raw: String) -> CollectionColor {
        CollectionColor(rawValue: raw) ?? .neutral
    }

    var label: String {
        switch self {
        case .neutral: "Default"
        case .red:     "Red"
        case .orange:  "Orange"
        case .yellow:  "Yellow"
        case .green:   "Green"
        case .teal:    "Teal"
        case .blue:    "Blue"
        case .purple:  "Purple"
        case .pink:    "Pink"
        }
    }
}
