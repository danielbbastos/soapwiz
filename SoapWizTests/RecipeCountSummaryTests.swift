import Testing
import Foundation
@testable import SoapWiz

/// The line under the Recipes title. Expected lines are built through the same
/// localized, inflected strings the production code uses, so the assertions
/// hold in any locale.
@Suite("Recipe count summary")
@MainActor
struct RecipeCountSummaryTests {

    private func expectedLine(total: Int, favorites: Int) -> String {
        var parts = [String(AttributedString(localized: "^[\(total) recipe](inflect: true)").characters)]
        if favorites > 0 {
            parts.append(String(AttributedString(localized: "^[\(favorites) favourite](inflect: true)").characters))
        }
        return parts.joined(separator: " · ")
    }

    private func parts(of line: String?) -> [String] {
        (line ?? "").components(separatedBy: " · ")
    }

    // MARK: - Counting

    @Test func counting_NoRecipes_IsZero() {
        #expect(RecipeCountSummary(counting: []) == RecipeCountSummary(total: 0, favorites: 0))
    }

    @Test func counting_MixedRecipes_CountsTotalAndFavourites() {
        let recipes = [
            Recipe.mock(name: "Aloe", isFavorite: true),
            Recipe.mock(name: "Basil"),
            Recipe.mock(name: "Cedar", isFavorite: true)
        ]

        #expect(RecipeCountSummary(counting: recipes) == RecipeCountSummary(total: 3, favorites: 2))
    }

    /// The title counts the whole collection: the search and the chips narrow
    /// the list, not the figures above it.
    @Test func counting_IgnoresSearchAndFilters() {
        let recipes = [Recipe.mock(name: "Aloe", isFavorite: true), Recipe.mock(name: "Basil")]
        let model = RecipeListViewModel()
        model.searchText = "aloe"

        #expect(model.filtered(recipes).count == 1)
        #expect(RecipeCountSummary(counting: recipes).total == 2)
    }

    // MARK: - Line

    @Test func line_NothingToCount_IsNil() {
        #expect(RecipeCountSummary(total: 0, favorites: 0).line == nil)
    }

    @Test func line_NoFavourites_HasOnlyTheTotal() {
        let line = RecipeCountSummary(total: 4, favorites: 0).line

        #expect(parts(of: line).count == 1)
        #expect(line == expectedLine(total: 4, favorites: 0))
    }

    @Test func line_WithFavourites_HasBothFigures() throws {
        let line = try #require(RecipeCountSummary(total: 18, favorites: 2).line)
        let split = parts(of: line)

        #expect(split.count == 2)
        #expect(split[0].contains(18.formatted()))
        #expect(split[1].contains(2.formatted()))
        #expect(line == expectedLine(total: 18, favorites: 2))
    }

    @Test func line_SingleAndMultiple_InflectDifferently() {
        let one = RecipeCountSummary(total: 1, favorites: 1).line
        let many = RecipeCountSummary(total: 5, favorites: 3).line

        #expect(one == expectedLine(total: 1, favorites: 1))
        #expect(many == expectedLine(total: 5, favorites: 3))
        #expect(one != many)
    }
}
