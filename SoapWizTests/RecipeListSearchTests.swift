import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Recipe list search", .serialized)
@MainActor
struct RecipeListSearchTests: RecipeCollectionTestHelpers {

    private let sut = RecipeListViewModel()

    private let recipes = [
        Recipe.mock(name: "Castile"),
        Recipe.mock(name: "Lavender Bar"),
        Recipe.mock(name: "Oatmeal Bar")
    ]

    @Test func filtered_EmptySearch_ReturnsEverything() {
        #expect(sut.filtered(recipes).count == 3)
    }

    @Test func filtered_Search_MatchesNamesCaseInsensitively() {
        sut.searchText = "BAR"

        #expect(sut.filtered(recipes).map(\.name) == ["Lavender Bar", "Oatmeal Bar"])
    }

    @Test func filtered_SearchWithNoMatch_IsEmpty() {
        sut.searchText = "Charcoal"

        #expect(sut.filtered(recipes).isEmpty)
    }

    @Test func filtered_WhitespaceOnlySearch_ReturnsEverything() {
        sut.searchText = "   "

        #expect(sut.filtered(recipes).count == 3)
    }

    @Test func filtered_SurroundingWhitespace_IsIgnored() {
        sut.searchText = " castile "

        #expect(sut.filtered(recipes).map(\.name) == ["Castile"])
    }

    /// Search and collections narrow together: a recipe must match the search
    /// and be filed under a selected collection.
    @Test func filtered_SearchAndCollection_MustBothMatch() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        sut.toggle(seeded.christmas)
        sut.searchText = "gift"

        #expect(sut.filtered(seeded.recipes).map(\.name) == ["Spiced Gift Bar"])
    }

    /// A search of only spaces filters nothing, so the empty state must not
    /// report it as a search that found nothing.
    @Test func isSearching_WhitespaceOnly_IsFalse() {
        sut.searchText = "   "

        #expect(sut.isSearching == false)
    }

    @Test func isSearching_WithText_IsTrue() {
        sut.searchText = " oat "

        #expect(sut.isSearching)
    }

    /// Search alone isn't a collection filter, so the All chip stays selected.
    @Test func hasActiveFilters_SearchOnly_IsFalse() {
        sut.searchText = "bar"

        #expect(sut.hasActiveFilters == false)
    }
}
