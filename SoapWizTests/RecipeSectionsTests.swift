import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Grouping the recipe list into favourites, recently added, and everything
/// else. The builder is pure, so `now` and the calendar are pinned rather than
/// read from the wall clock.
@Suite("Recipe sections")
@MainActor
struct RecipeSectionsTests {

    private let sut = RecipeListViewModel()
    private let calendar = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now)!
    }

    private func hoursAgo(_ hours: Int) -> Date {
        calendar.date(byAdding: .hour, value: -hours, to: now)!
    }

    private func sections(_ recipes: [Recipe]) -> RecipeSections {
        sut.sections(recipes, now: now, calendar: calendar)
    }

    // MARK: - Recent group membership

    @Test func recent_CreatedWithinThreeDays_IsRecent() {
        let fresh = Recipe.mock(name: "Aloe", createdAt: hoursAgo(2))

        #expect(sections([fresh]).recent.map(\.name) == ["Aloe"])
    }

    @Test func recent_OlderThanThreeDays_IsNotRecent() {
        let old = Recipe.mock(name: "Aloe", createdAt: daysAgo(4))

        let result = sections([old])
        #expect(result.recent.isEmpty)
        #expect(result.others.map(\.name) == ["Aloe"])
    }

    /// The window is inclusive at its far edge: a recipe created exactly at the
    /// cutoff still counts as recent.
    @Test func recent_AtTheCutoffBoundary_IsRecent() {
        let boundary = Recipe.mock(name: "Aloe", createdAt: daysAgo(3))

        #expect(sections([boundary]).recent.map(\.name) == ["Aloe"])
    }

    @Test func recent_NoCreationDate_IsNeverRecent() {
        let dateless = Recipe.mock(name: "Aloe", createdAt: nil)

        let result = sections([dateless])
        #expect(result.recent.isEmpty)
        #expect(result.others.map(\.name) == ["Aloe"])
    }

    // MARK: - Ordering and capping

    @Test func recent_SortsNewestFirstRegardlessOfName() {
        // Passed in the A→Z order the @Query establishes.
        let recipes = [
            Recipe.mock(name: "Aloe", createdAt: daysAgo(2)),
            Recipe.mock(name: "Basil", createdAt: hoursAgo(1)),
            Recipe.mock(name: "Cedar", createdAt: daysAgo(1))
        ]

        #expect(sections(recipes).recent.map(\.name) == ["Basil", "Cedar", "Aloe"])
    }

    @Test func recent_MoreThanThree_CapsAtThreeAndSpillsToOthers() {
        let recipes = [
            Recipe.mock(name: "Aloe", createdAt: daysAgo(1)),
            Recipe.mock(name: "Basil", createdAt: hoursAgo(1)),
            Recipe.mock(name: "Cedar", createdAt: hoursAgo(2)),
            Recipe.mock(name: "Dill", createdAt: hoursAgo(3))
        ]

        let result = sections(recipes)
        // The three newest are recent; the oldest of the four spills to others.
        #expect(result.recent.map(\.name) == ["Basil", "Cedar", "Dill"])
        #expect(result.others.map(\.name) == ["Aloe"])
    }

    @Test func others_KeepAlphabeticalOrder() {
        let recipes = [
            Recipe.mock(name: "Aloe", createdAt: daysAgo(10)),
            Recipe.mock(name: "Basil", createdAt: hoursAgo(1)),
            Recipe.mock(name: "Cedar", createdAt: nil)
        ]

        let result = sections(recipes)
        #expect(result.recent.map(\.name) == ["Basil"])
        #expect(result.others.map(\.name) == ["Aloe", "Cedar"])
    }

    @Test func recent_DoesNotRepeatInOthers() {
        let recent = Recipe.mock(name: "Basil", createdAt: hoursAgo(1))
        let result = sections([recent])

        #expect(result.recent.map(\.name) == ["Basil"])
        #expect(result.others.isEmpty)
    }

    // MARK: - Favourites win over recency

    @Test func favourite_ExcludedFromRecentEvenWhenFresh() {
        let pinned = Recipe.mock(name: "Aloe", isFavorite: true, createdAt: hoursAgo(1))

        let result = sections([pinned])
        #expect(result.favorites.map(\.name) == ["Aloe"])
        #expect(result.recent.isEmpty)
        #expect(result.others.isEmpty)
    }

    @Test func favourites_KeepAlphabeticalOrder() {
        let recipes = [
            Recipe.mock(name: "Aloe", isFavorite: true, createdAt: hoursAgo(1)),
            Recipe.mock(name: "Cedar", isFavorite: true, createdAt: daysAgo(10))
        ]

        #expect(sections(recipes).favorites.map(\.name) == ["Aloe", "Cedar"])
    }

    // MARK: - Sectioning and emptiness

    @Test func isSectioned_OnlyWhenSomethingIsRecent() {
        let recipes = [
            Recipe.mock(name: "Aloe", isFavorite: true, createdAt: hoursAgo(1)),
            Recipe.mock(name: "Basil", createdAt: daysAgo(10))
        ]

        #expect(sections(recipes).isSectioned == false)
    }

    @Test func isSectioned_TrueWithARecentRecipe() {
        let recipes = [Recipe.mock(name: "Basil", createdAt: hoursAgo(1))]

        #expect(sections(recipes).isSectioned)
    }

    @Test func emptyInput_ProducesEmptySections() {
        let result = sections([])
        #expect(result.isEmpty)
        #expect(result.isSectioned == false)
    }

    // MARK: - Model default

    @Test func createdAt_NewRecipe_IsStampedAtCreation() throws {
        let before = Date()
        let recipe = Recipe(name: "Castile")
        let after = Date()

        let created = try #require(recipe.createdAt)
        #expect(created >= before && created <= after)
    }
}
