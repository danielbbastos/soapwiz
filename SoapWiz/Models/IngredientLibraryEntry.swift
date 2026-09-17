import Foundation

/// One ingredient in the bundled `IngredientLibrary`: what it is, never what the
/// user paid for it or how much is left.
struct IngredientLibraryEntry: Decodable {
    /// Permanent once shipped. Installed rows, backups and shared recipes all
    /// refer to the entry by it.
    let slug: String
    let name: String
    /// Other names the same ingredient goes by, used only to recognise an
    /// ingredient the user created before the library existed.
    let aliases: [String]
    /// One of `IngredientCategory.Name`.
    let category: String
    /// Raw value of `IngredientUnit`.
    let unit: String
    let sapValue: Double?
    let kohSapValue: Double?
    let density: Double?
    let fattyAcidProfile: FattyAcidProfile?

    /// Every name this entry answers to — the one it ships under and each alias —
    /// folded for lookup. The single definition of "a name that means this entry",
    /// shared by the installer's adoption pass and `IngredientLibrary.entry(matching:)`
    /// so the two can never disagree about what counts as a match.
    var lookupNames: [String] {
        ([name] + aliases).map(\.lookupKey).filter { !$0.isEmpty }
    }

    func hasSameChemistry(as ingredient: Ingredient) -> Bool {
        sapValue == ingredient.sapValue
            && kohSapValue == ingredient.kohSapValue
            && density == ingredient.density
            && fattyAcidProfile == ingredient.fattyAcidProfile
    }
}

/// The on-disk shape of `IngredientLibrary.json`.
struct IngredientLibraryFile: Decodable {
    let entries: [IngredientLibraryEntry]
}
