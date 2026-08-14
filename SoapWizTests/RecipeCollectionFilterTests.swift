import Testing
import Foundation
import SwiftData
@testable import SoapWiz

// MARK: - List filtering

@Suite("Recipe list collection filter", .serialized)
@MainActor
struct RecipeListCollectionFilterTests: RecipeCollectionTestHelpers {

    @Test func filtered_NoSelection_ReturnsEverything() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let model = RecipeListViewModel()

        #expect(model.filtered(seeded.recipes).count == 4)
        #expect(model.hasActiveFilters == false)
    }

    @Test func filtered_OneCollection_ReturnsOnlyItsRecipes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let model = RecipeListViewModel()
        model.toggle(seeded.christmas)

        let names = Set(model.filtered(seeded.recipes).map(\.name))
        #expect(names == ["Cinnamon Bar", "Spiced Gift Bar"])
        #expect(model.hasActiveFilters)
    }

    /// A recipe in two collections must appear under either filter — the case the
    /// many-to-many model exists to serve.
    @Test func filtered_RecipeInTwoCollections_AppearsUnderBothFilters() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)

        for collection in [seeded.christmas, seeded.gifts] {
            let model = RecipeListViewModel()
            model.toggle(collection)
            #expect(model.filtered(seeded.recipes).contains { $0.name == "Spiced Gift Bar" })
        }
    }

    /// Union, not intersection: selecting both piles asks for both, and the
    /// recipe filed under only one of them is still one the user meant to see.
    @Test func filtered_MultiSelect_ReturnsTheUnionWithoutDuplicates() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let model = RecipeListViewModel()
        model.toggle(seeded.christmas)
        model.toggle(seeded.gifts)

        let filtered = model.filtered(seeded.recipes)
        #expect(filtered.count == 3)
        #expect(Set(filtered.map(\.name)) == ["Cinnamon Bar", "Lavender Bar", "Spiced Gift Bar"])
    }

    @Test func filtered_EmptyCollection_ReturnsNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let empty = RecipeCollection(name: "Shampoo bars")
        ctx.insert(empty)
        try ctx.save()

        let model = RecipeListViewModel()
        model.toggle(empty)

        #expect(model.filtered(seeded.recipes).isEmpty)
    }

    @Test func filtered_EmptyRecipeList_ReturnsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let model = RecipeListViewModel()
        model.toggle(seeded.gifts)

        #expect(model.filtered([]).isEmpty)
    }

    @Test func toggle_Twice_ClearsTheSelection() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let model = RecipeListViewModel()

        model.toggle(seeded.gifts)
        model.toggle(seeded.gifts)

        #expect(model.hasActiveFilters == false)
        #expect(model.filtered(seeded.recipes).count == 4)
    }

    @Test func clearFilters_WithSelection_RestoresTheWholeList() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let model = RecipeListViewModel()
        model.toggle(seeded.christmas)

        model.clearFilters()

        #expect(model.selectedCollections.isEmpty)
        #expect(model.filtered(seeded.recipes).count == 4)
    }

    /// Without pruning, a selection left pointing at a deleted row silently
    /// matches nothing — an empty list with no chip on screen to explain it.
    @Test func pruneSelectedCollections_CollectionGone_DropsTheStaleSelection() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let model = RecipeListViewModel()
        model.toggle(seeded.christmas)
        model.toggle(seeded.gifts)

        model.pruneSelectedCollections(against: [seeded.gifts])

        #expect(model.selectedCollections == [seeded.gifts.persistentModelID])
        #expect(Set(model.filtered(seeded.recipes).map(\.name)) == ["Lavender Bar", "Spiced Gift Bar"])
    }

    @Test func pruneSelectedCollections_EveryCollectionGone_ShowsTheWholeList() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let model = RecipeListViewModel()
        model.toggle(seeded.christmas)

        model.pruneSelectedCollections(against: [])

        #expect(model.hasActiveFilters == false)
        #expect(model.filtered(seeded.recipes).count == 4)
    }

    @Test func pruneSelectedCollections_NothingSelected_ChangesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let model = RecipeListViewModel()

        model.pruneSelectedCollections(against: [seeded.christmas])

        #expect(model.selectedCollections.isEmpty)
    }

    // MARK: - Filing from the row menu

    @Test func toggleMembership_UnfiledRecipe_FilesIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let plain = try seeded.recipe(named: "Castile")
        let model = RecipeListViewModel()

        model.toggleMembership(of: plain, in: seeded.christmas)
        try ctx.save()

        #expect(plain.isFiled(under: seeded.christmas))
        #expect(seeded.christmas.recipes.contains { $0.name == "Castile" })
    }

    @Test func toggleMembership_FiledRecipe_UnfilesIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let cinnamon = try seeded.recipe(named: "Cinnamon Bar")
        let model = RecipeListViewModel()

        model.toggleMembership(of: cinnamon, in: seeded.christmas)
        try ctx.save()

        #expect(cinnamon.isFiled(under: seeded.christmas) == false)
        #expect(cinnamon.collections.isEmpty)
        #expect(seeded.christmas.recipes.contains { $0.name == "Cinnamon Bar" } == false)
    }

    /// Filing from the menu is multi-select: a second collection joins the first
    /// rather than replacing it.
    @Test func toggleMembership_SecondCollection_KeepsTheFirst() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let cinnamon = try seeded.recipe(named: "Cinnamon Bar")
        let model = RecipeListViewModel()

        model.toggleMembership(of: cinnamon, in: seeded.gifts)
        try ctx.save()

        #expect(Set(cinnamon.collections.map(\.name)) == ["Christmas", "Gifts"])
    }

    @Test func toggleMembership_TwiceInARow_LeavesTheRecipeAsItWas() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let plain = try seeded.recipe(named: "Castile")
        let model = RecipeListViewModel()

        model.toggleMembership(of: plain, in: seeded.gifts)
        model.toggleMembership(of: plain, in: seeded.gifts)
        try ctx.save()

        #expect(plain.collections.isEmpty)
    }

    /// Unfiling a recipe while its collection is the active filter has to drop
    /// it out of the filtered list on the spot.
    @Test func toggleMembership_WhileFiltered_RemovesTheRowFromTheResults() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let cinnamon = try seeded.recipe(named: "Cinnamon Bar")
        let model = RecipeListViewModel()
        model.toggle(seeded.christmas)
        #expect(model.filtered(seeded.recipes).count == 2)

        model.toggleMembership(of: cinnamon, in: seeded.christmas)

        #expect(Set(model.filtered(seeded.recipes).map(\.name)) == ["Spiced Gift Bar"])
    }

    @Test func duplicate_FromTheRowMenu_InsertsACopyAlongsideTheOriginal() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seedCollections(ctx)
        let cinnamon = try seeded.recipe(named: "Cinnamon Bar")
        let model = RecipeListViewModel()

        let copy = model.duplicate(cinnamon, among: seeded.recipes, context: ctx)
        try ctx.save()

        #expect(copy.name == "Cinnamon Bar (copy)")
        #expect(copy.collections.map(\.name) == ["Christmas"])
        #expect(try ctx.fetch(FetchDescriptor<Recipe>()).count == 5)
    }
}
