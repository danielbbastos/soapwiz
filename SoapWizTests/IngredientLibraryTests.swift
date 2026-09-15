import Testing
import Foundation
@testable import SoapWiz

@Suite("Ingredient library")
@MainActor
struct IngredientLibraryTests {

    // MARK: - Bundled file

    @Test func bundled_Decodes_WithEntries() {
        #expect(!IngredientLibrary.bundled.entries.isEmpty)
    }

    @Test func bundled_Slugs_AreUniqueAndNotEmpty() {
        let slugs = IngredientLibrary.bundled.entries.map(\.slug)
        #expect(slugs.allSatisfy { !$0.isEmpty })
        #expect(slugs.count == Set(slugs).count)
    }

    @Test func bundled_Categories_AreKnownCategoryNames() {
        let unknown = IngredientLibrary.bundled.entries.filter { !IngredientCategory.Name.all.contains($0.category) }
        #expect(unknown.isEmpty, "Unknown categories: \(unknown.map(\.slug))")
    }

    @Test func bundled_Units_AreIngredientUnits() {
        let unknown = IngredientLibrary.bundled.entries.filter { IngredientUnit(rawValue: $0.unit) == nil }
        #expect(unknown.isEmpty, "Unknown units: \(unknown.map(\.slug))")
    }

    @Test func load_BundleWithoutTheFile_ReturnsAnEmptyLibrary() {
        #expect(IngredientLibrary.load(from: Bundle(for: BundleMarker.self)).entries.isEmpty)
    }

    // MARK: - Chemistry

    @Test func hasSameChemistry_IdenticalValues_IsTrue() {
        let entry = IngredientLibraryEntry.mock()
        let ingredient = Ingredient.mock(matching: entry)
        #expect(entry.hasSameChemistry(as: ingredient))
    }

    @Test func hasSameChemistry_DifferentSapValue_IsFalse() {
        let entry = IngredientLibraryEntry.mock()
        let ingredient = Ingredient.mock(matching: entry)
        ingredient.sapValue = 0.2
        #expect(!entry.hasSameChemistry(as: ingredient))
    }

    @Test func hasSameChemistry_MissingFattyAcidProfile_IsFalse() {
        let entry = IngredientLibraryEntry.mock()
        let ingredient = Ingredient.mock(matching: entry)
        ingredient.fattyAcidProfile = nil
        #expect(!entry.hasSameChemistry(as: ingredient))
    }

    // MARK: - isLibrary

    @Test func isLibrary_UserCreated_IsFalse() {
        #expect(!Ingredient(name: "House Blend").isLibrary)
    }

    @Test func isLibrary_InstalledFromTheLibrary_IsTrue() {
        let ingredient = Ingredient(name: "Olive Oil")
        ingredient.librarySlug = "olive-oil"
        #expect(ingredient.isLibrary)
    }

    @Test func isLibrary_WithCustomChemistry_IsFalse() {
        let ingredient = Ingredient(name: "Olive Oil")
        ingredient.librarySlug = "olive-oil"
        ingredient.hasCustomChemistry = true
        #expect(!ingredient.isLibrary)
    }
}

/// The test bundle, which never carries `IngredientLibrary.json`.
private final class BundleMarker {}

extension IngredientLibraryEntry {
    static func mock(
        slug: String = "olive-oil",
        name: String = "Olive Oil",
        aliases: [String] = [],
        category: String = IngredientCategory.Name.oils,
        unit: String = IngredientUnit.grams.rawValue,
        sapValue: Double? = 0.135,
        kohSapValue: Double? = 0.19,
        density: Double? = 0.912,
        fattyAcidProfile: FattyAcidProfile? = FattyAcidProfile(palmitic: 14, stearic: 3, oleic: 69, linoleic: 12, linolenic: 1)
    ) -> IngredientLibraryEntry {
        IngredientLibraryEntry(
            slug: slug,
            name: name,
            aliases: aliases,
            category: category,
            unit: unit,
            sapValue: sapValue,
            kohSapValue: kohSapValue,
            density: density,
            fattyAcidProfile: fattyAcidProfile
        )
    }
}

extension Ingredient {
    /// A user-created ingredient carrying exactly the entry's chemistry.
    static func mock(matching entry: IngredientLibraryEntry, name: String? = nil) -> Ingredient {
        let ingredient = Ingredient(name: name ?? entry.name, unit: entry.unit)
        ingredient.sapValue = entry.sapValue
        ingredient.kohSapValue = entry.kohSapValue
        ingredient.density = entry.density
        ingredient.fattyAcidProfile = entry.fattyAcidProfile
        return ingredient
    }
}
