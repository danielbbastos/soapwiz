import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Collections are a many-to-many overlay over the flat recipe list: a recipe
/// belongs to several at once, and deleting one is a filing decision that must
/// never reach the recipes themselves.
@Suite("Recipe collections", .serialized)
@MainActor
struct RecipeCollectionTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    // MARK: - Membership

    @Test func collections_NewRecipe_StartsUnfiled() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)
        try ctx.save()

        #expect(recipe.collections.isEmpty)
    }

    @Test func collections_RecipeInTwo_IsListedByBoth() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(gifts)
        ctx.insert(recipe)
        recipe.collections = [christmas, gifts]
        try ctx.save()

        #expect(recipe.collections.count == 2)
        #expect(christmas.recipes.map(\.name) == ["Cinnamon Bar"])
        #expect(gifts.recipes.map(\.name) == ["Cinnamon Bar"])
    }

    @Test func collections_ManyRecipesOneCollection_AllAppearOnTheInverse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(gifts)
        for name in ["Castile", "Bastille", "Coconut Bar"] {
            let recipe = Recipe(name: name)
            ctx.insert(recipe)
            recipe.collections = [gifts]
        }
        try ctx.save()

        #expect(Set(gifts.recipes.map(\.name)) == ["Castile", "Bastille", "Coconut Bar"])
    }

    // MARK: - Deletion

    /// The `.nullify` rule in both directions is the point of the whole model: a
    /// collection is a label, and removing a label must not remove what it named.
    @Test func deleteCollection_NullifiesLinkAndKeepsRecipes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(recipe)
        recipe.collections = [christmas]
        try ctx.save()

        ctx.delete(christmas)
        try ctx.save()

        let recipes = try ctx.fetch(FetchDescriptor<Recipe>())
        #expect(recipes.count == 1)
        #expect(recipes.first?.collections.isEmpty == true)
    }

    @Test func deleteCollection_RecipeInTwo_KeepsTheOtherMembership() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(gifts)
        ctx.insert(recipe)
        recipe.collections = [christmas, gifts]
        try ctx.save()

        ctx.delete(christmas)
        try ctx.save()

        #expect(recipe.collections.map(\.name) == ["Gifts"])
    }

    @Test func deleteRecipe_KeepsCollectionAlive() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        let recipe = Recipe(name: "Castile")
        ctx.insert(gifts)
        ctx.insert(recipe)
        recipe.collections = [gifts]
        try ctx.save()

        ctx.delete(recipe)
        try ctx.save()

        let collections = try ctx.fetch(FetchDescriptor<RecipeCollection>())
        #expect(collections.count == 1)
        #expect(collections.first?.recipes.isEmpty == true)
    }

    // MARK: - Colour

    @Test func color_EmptyColorName_ResolvesToNeutral() {
        #expect(RecipeCollection(name: "Gifts").color == .neutral)
    }

    @Test func color_UnknownColorName_ResolvesToNeutral() {
        #expect(RecipeCollection(name: "Gifts", colorName: "chartreuse").color == .neutral)
    }

    @Test func color_KnownColorName_ResolvesToThatCase() {
        #expect(RecipeCollection(name: "Gifts", colorName: "teal").color == .teal)
    }

    // MARK: - Sorting

    @Test func sortedByName_MixedCaseAndAccents_OrdersByLookupKey() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let collections = ["gifts", "Áutumn", "Christmas"].map { RecipeCollection(name: $0) }
        collections.forEach { ctx.insert($0) }
        try ctx.save()

        #expect(collections.sortedByName.map(\.name) == ["Áutumn", "Christmas", "gifts"])
    }

    /// Two rows sharing a name is the unmerged-CloudKit-duplicate case. The order
    /// has to be stable anyway, or the recipe form's dirty check fires on its own.
    @Test func sortedByName_SameName_BreaksTieOnUUIDDeterministically() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let low = RecipeCollection(name: "Gifts")
        low.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let high = RecipeCollection(name: "Gifts")
        high.uuid = try #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))
        ctx.insert(low)
        ctx.insert(high)
        try ctx.save()

        #expect([high, low].sortedByName.map(\.uuid) == [low.uuid, high.uuid])
        #expect([low, high].sortedByName.map(\.uuid) == [low.uuid, high.uuid])
    }

    @Test func sortedByName_Empty_ReturnsEmpty() {
        #expect([RecipeCollection]().sortedByName.isEmpty)
    }
}

// MARK: - List filtering

@Suite("Recipe list collection filter", .serialized)
@MainActor
struct RecipeListCollectionFilterTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    /// Three recipes: one filed under Christmas, one under Gifts, one under both,
    /// plus one unfiled.
    private func seed(_ ctx: ModelContext) throws -> (
        christmas: RecipeCollection, gifts: RecipeCollection, recipes: [Recipe]
    ) {
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(christmas)
        ctx.insert(gifts)

        let cinnamon = Recipe(name: "Cinnamon Bar")
        let lavender = Recipe(name: "Lavender Bar")
        let both = Recipe(name: "Spiced Gift Bar")
        let plain = Recipe(name: "Castile")
        for recipe in [cinnamon, lavender, both, plain] {
            ctx.insert(recipe)
        }
        cinnamon.collections = [christmas]
        lavender.collections = [gifts]
        both.collections = [christmas, gifts]
        try ctx.save()

        return (christmas, gifts, [cinnamon, lavender, both, plain])
    }

    @Test func filtered_NoSelection_ReturnsEverything() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seed(ctx)
        let model = RecipeListViewModel()

        #expect(model.filtered(seeded.recipes).count == 4)
        #expect(model.hasActiveFilters == false)
    }

    @Test func filtered_OneCollection_ReturnsOnlyItsRecipes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seed(ctx)
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
        let seeded = try seed(ctx)

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
        let seeded = try seed(ctx)
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
        let seeded = try seed(ctx)
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
        let seeded = try seed(ctx)
        let model = RecipeListViewModel()
        model.toggle(seeded.gifts)

        #expect(model.filtered([]).isEmpty)
    }

    @Test func toggle_Twice_ClearsTheSelection() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seed(ctx)
        let model = RecipeListViewModel()

        model.toggle(seeded.gifts)
        model.toggle(seeded.gifts)

        #expect(model.hasActiveFilters == false)
        #expect(model.filtered(seeded.recipes).count == 4)
    }

    @Test func clearFilters_WithSelection_RestoresTheWholeList() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seed(ctx)
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
        let seeded = try seed(ctx)
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
        let seeded = try seed(ctx)
        let model = RecipeListViewModel()
        model.toggle(seeded.christmas)

        model.pruneSelectedCollections(against: [])

        #expect(model.hasActiveFilters == false)
        #expect(model.filtered(seeded.recipes).count == 4)
    }

    @Test func pruneSelectedCollections_NothingSelected_ChangesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seed(ctx)
        let model = RecipeListViewModel()

        model.pruneSelectedCollections(against: [seeded.christmas])

        #expect(model.selectedCollections.isEmpty)
    }

    // MARK: - Filing from the row menu

    @Test func toggleMembership_UnfiledRecipe_FilesIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seed(ctx)
        let plain = try #require(seeded.recipes.first { $0.name == "Castile" })
        let model = RecipeListViewModel()

        model.toggleMembership(of: plain, in: seeded.christmas)
        try ctx.save()

        #expect(plain.isFiled(under: seeded.christmas))
        #expect(seeded.christmas.recipes.contains { $0.name == "Castile" })
    }

    @Test func toggleMembership_FiledRecipe_UnfilesIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seed(ctx)
        let cinnamon = try #require(seeded.recipes.first { $0.name == "Cinnamon Bar" })
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
        let seeded = try seed(ctx)
        let cinnamon = try #require(seeded.recipes.first { $0.name == "Cinnamon Bar" })
        let model = RecipeListViewModel()

        model.toggleMembership(of: cinnamon, in: seeded.gifts)
        try ctx.save()

        #expect(Set(cinnamon.collections.map(\.name)) == ["Christmas", "Gifts"])
    }

    @Test func toggleMembership_TwiceInARow_LeavesTheRecipeAsItWas() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seed(ctx)
        let plain = try #require(seeded.recipes.first { $0.name == "Castile" })
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
        let seeded = try seed(ctx)
        let cinnamon = try #require(seeded.recipes.first { $0.name == "Cinnamon Bar" })
        let model = RecipeListViewModel()
        model.toggle(seeded.christmas)
        #expect(model.filtered(seeded.recipes).count == 2)

        model.toggleMembership(of: cinnamon, in: seeded.christmas)

        #expect(Set(model.filtered(seeded.recipes).map(\.name)) == ["Spiced Gift Bar"])
    }

    @Test func duplicate_FromTheRowMenu_InsertsACopyAlongsideTheOriginal() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let seeded = try seed(ctx)
        let cinnamon = try #require(seeded.recipes.first { $0.name == "Cinnamon Bar" })
        let model = RecipeListViewModel()

        let copy = model.duplicate(cinnamon, among: seeded.recipes, context: ctx)
        try ctx.save()

        #expect(copy.name == "Cinnamon Bar (copy)")
        #expect(copy.collections.map(\.name) == ["Christmas"])
        #expect(try ctx.fetch(FetchDescriptor<Recipe>()).count == 5)
    }
}

// MARK: - Settings screens

@Suite("Recipe collection form view model", .serialized)
@MainActor
struct RecipeCollectionFormViewModelTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    @Test func isValid_BlankName_IsFalse() {
        let model = RecipeCollectionFormViewModel()
        model.name = "   "

        #expect(model.isValid(among: []) == false)
    }

    @Test func isDuplicate_NameDifferingByCaseAndSpacing_IsTrue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let existing = RecipeCollection(name: "Christmas")
        ctx.insert(existing)
        let model = RecipeCollectionFormViewModel()
        model.name = "  christmas "

        #expect(model.isDuplicate(among: [existing]))
        #expect(model.isValid(among: [existing]) == false)
    }

    /// Editing a collection without renaming it must not report the collection as
    /// its own duplicate.
    @Test func isDuplicate_EditingItself_IsFalse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let existing = RecipeCollection(name: "Christmas")
        ctx.insert(existing)
        let model = RecipeCollectionFormViewModel(collection: existing)

        #expect(model.isDuplicate(among: [existing]) == false)
        #expect(model.isValid(among: [existing]))
    }

    @Test func save_NewCollection_InsertsWithTrimmedNameAndColor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeCollectionFormViewModel()
        model.name = "  Gifts  "
        model.color = .teal

        let saved = model.save(context: ctx)
        try ctx.save()

        #expect(saved.name == "Gifts")
        #expect(saved.colorName == "teal")
        #expect(try ctx.fetch(FetchDescriptor<RecipeCollection>()).count == 1)
    }

    @Test func save_ExistingCollection_MutatesItAndKeepsItsRecipes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let collection = RecipeCollection(name: "Xmas")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(collection)
        ctx.insert(recipe)
        recipe.collections = [collection]
        try ctx.save()

        let model = RecipeCollectionFormViewModel(collection: collection)
        model.name = "Christmas"
        model.color = .red
        model.save(context: ctx)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<RecipeCollection>()).count == 1)
        #expect(collection.name == "Christmas")
        #expect(collection.color == .red)
        #expect(collection.recipes.count == 1)
    }

    @Test func init_ExistingCollection_LoadsNameAndColor() {
        let model = RecipeCollectionFormViewModel(
            collection: RecipeCollection(name: "Gifts", colorName: "purple")
        )

        #expect(model.name == "Gifts")
        #expect(model.color == .purple)
        #expect(model.isEditing)
    }
}

@Suite("Recipe collection list view model", .serialized)
@MainActor
struct RecipeCollectionListViewModelTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    @Test func delete_InUseCollection_ConfirmsRatherThanBlocking() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(recipe)
        recipe.collections = [christmas]
        try ctx.save()

        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [christmas])

        #expect(model.confirmingDelete.count == 1)
        #expect(try ctx.fetch(FetchDescriptor<RecipeCollection>()).count == 1)
    }

    @Test func confirmDelete_RemovesCollectionAndLeavesRecipesIntact() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(recipe)
        recipe.collections = [christmas]
        try ctx.save()

        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [christmas])
        model.confirmDelete(context: ctx)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<RecipeCollection>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Recipe>()).count == 1)
        #expect(recipe.collections.isEmpty)
        #expect(model.confirmingDelete.isEmpty)
    }

    @Test func delete_OutOfRangeOffset_StagesNothing() {
        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet(integer: 3), in: [RecipeCollection(name: "Gifts")])

        #expect(model.confirmingDelete.isEmpty)
    }

    @Test func deleteConfirmationMessage_NothingStaged_IsEmpty() {
        #expect(RecipeCollectionListViewModel().deleteConfirmationMessage.isEmpty)
    }

    @Test func deleteConfirmationMessage_EmptyCollection_DoesNotMentionRecipes() {
        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [RecipeCollection(name: "Gifts")])

        #expect(model.deleteConfirmationMessage == "Delete \"Gifts\"? This can't be undone.")
    }

    /// The promise that recipes survive is the reason this alert confirms instead
    /// of blocking, so the wording is asserted rather than left to the view.
    @Test func deleteConfirmationMessage_CollectionWithRecipes_PromisesTheyAreKept() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        ctx.insert(christmas)
        for name in ["Cinnamon Bar", "Spiced Gift Bar"] {
            let recipe = Recipe(name: name)
            ctx.insert(recipe)
            recipe.collections = [christmas]
        }
        try ctx.save()

        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [christmas])

        #expect(model.deleteConfirmationMessage
            == "Delete \"Christmas\"? Its 2 recipes are kept and simply unfiled.")
    }

    @Test func deleteConfirmationMessage_SingleRecipe_UsesTheSingular() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(recipe)
        recipe.collections = [christmas]
        try ctx.save()

        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [christmas])

        #expect(model.deleteConfirmationMessage
            == "Delete \"Christmas\"? Its 1 recipe is kept and simply unfiled.")
    }

    @Test func deleteConfirmationMessage_SeveralCollections_CountsThemTogether() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(gifts)
        ctx.insert(recipe)
        recipe.collections = [christmas, gifts]
        try ctx.save()

        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet([0, 1]), in: [christmas, gifts])

        #expect(model.deleteConfirmationMessage
            == "Delete 2 collections? Their 2 recipes are kept and simply unfiled.")
    }
}

// MARK: - Recipe form

@Suite("Recipe form collections", .serialized)
@MainActor
struct RecipeFormCollectionTests: RecipeFormTestHelpers {

    @Test func selectedCollections_NewForm_IsEmpty() {
        #expect(RecipeFormViewModel().selectedCollections.isEmpty)
    }

    @Test func toggleCollection_Once_SelectsIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(gifts)
        let model = RecipeFormViewModel()

        model.toggleCollection(gifts)

        #expect(model.isSelected(gifts))
        #expect(model.selectedCollections.count == 1)
    }

    @Test func toggleCollection_Twice_DeselectsIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(gifts)
        let model = RecipeFormViewModel()

        model.toggleCollection(gifts)
        model.toggleCollection(gifts)

        #expect(model.isSelected(gifts) == false)
        #expect(model.selectedCollections.isEmpty)
    }

    /// Selection order must not leak into the stored order, or the dirty check
    /// would fire on a recipe the user only re-picked in a different sequence.
    @Test func toggleCollection_SelectedOutOfOrder_StaysSortedByName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        let christmas = RecipeCollection(name: "Christmas")
        ctx.insert(gifts)
        ctx.insert(christmas)
        let model = RecipeFormViewModel()

        model.toggleCollection(gifts)
        model.toggleCollection(christmas)

        #expect(model.selectedCollections.map(\.name) == ["Christmas", "Gifts"])
    }

    @Test func collectionsLabel_NoneSelected_ReadsNone() {
        #expect(RecipeFormViewModel().collectionsLabel == "None")
    }

    @Test func collectionsLabel_OneSelected_ReadsItsName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(gifts)
        let model = RecipeFormViewModel()
        model.toggleCollection(gifts)

        #expect(model.collectionsLabel == "Gifts")
    }

    @Test func collectionsLabel_SeveralSelected_CountsThem() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let collections = ["Gifts", "Christmas"].map { RecipeCollection(name: $0) }
        collections.forEach { ctx.insert($0) }
        let model = RecipeFormViewModel()
        collections.forEach { model.toggleCollection($0) }

        #expect(model.collectionsLabel == "2 selected")
    }

    // MARK: - Persistence

    @Test func save_WithCollections_FilesTheRecipeUnderEach() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(christmas)
        ctx.insert(gifts)

        let model = RecipeFormViewModel()
        model.name = "Cinnamon Bar"
        model.toggleCollection(christmas)
        model.toggleCollection(gifts)
        let recipe = model.save(context: ctx)
        try ctx.save()

        #expect(Set(recipe.collections.map(\.name)) == ["Christmas", "Gifts"])
        #expect(christmas.recipes.map(\.name) == ["Cinnamon Bar"])
    }

    @Test func save_NoCollections_LeavesTheRecipeUnfiled() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.name = "Castile"
        let recipe = model.save(context: ctx)
        try ctx.save()

        #expect(recipe.collections.isEmpty)
    }

    @Test func load_FiledRecipe_ReadsItsCollectionsSorted() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(gifts)
        ctx.insert(recipe)
        recipe.collections = [gifts, christmas]
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.selectedCollections.map(\.name) == ["Christmas", "Gifts"])
        #expect(model.isSelected(gifts))
    }

    @Test func save_AfterDeselecting_UnfilesTheRecipe() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(recipe)
        recipe.collections = [christmas]
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.toggleCollection(christmas)
        model.save(context: ctx)
        try ctx.save()

        #expect(recipe.collections.isEmpty)
        #expect(christmas.recipes.isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<RecipeCollection>()).count == 1)
    }

    // MARK: - Unsaved changes

    @Test func isDirty_CollectionToggled_IsTrue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(gifts)
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        model.toggleCollection(gifts)

        #expect(model.isDirty)
    }

    @Test func isDirty_CollectionToggledBackOff_IsFalseAgain() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(gifts)
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        model.toggleCollection(gifts)
        model.toggleCollection(gifts)

        #expect(model.isDirty == false)
    }

    @Test func isDirty_LoadedFiledRecipeUntouched_IsFalse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(gifts)
        ctx.insert(recipe)
        recipe.collections = [gifts, christmas]
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.captureSnapshot()

        #expect(model.isDirty == false)
    }
}
