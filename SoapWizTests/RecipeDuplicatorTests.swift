import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Recipe duplicator", .serialized)
@MainActor
struct RecipeDuplicatorTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    /// A recipe with two oils, an additive, a fragrance, a product, a lye
    /// ingredient and a collection — enough that a shallow copy would show up.
    @discardableResult
    private func seedRecipe(_ ctx: ModelContext, name: String = "Castile") -> Recipe {
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let coconut = Ingredient(name: "Coconut Oil", unit: "g")
        let lactate = Ingredient(name: "Sodium Lactate", unit: "g")
        let lavender = Ingredient(name: "Lavender EO", unit: "g")
        let lye = Ingredient(name: "Sodium Hydroxide", unit: "g")
        for ingredient in [olive, coconut, lactate, lavender, lye] {
            ctx.insert(ingredient)
        }
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(gifts)

        let recipe = Recipe(name: name, desc: "A gentle bar")
        recipe.totalOilWeight = 1200
        recipe.superFat = 7
        recipe.waterParts = 2
        recipe.useCFM = true
        recipe.cfmNeutralizer = CFMNeutralizer.borax.rawValue
        recipe.fragranceUnit = FragranceUnit.percentOfFragrances.rawValue
        recipe.lyeIngredient = lye
        recipe.collections = [gifts]
        ctx.insert(recipe)

        for (ingredient, pct) in [(olive, 70.0), (coconut, 30.0)] {
            let line = RecipeIngredient(ingredient: ingredient, percentage: pct, role: .oil)
            line.recipe = recipe
            ctx.insert(line)
        }
        let additive = RecipeIngredient(ingredient: lactate, percentage: 0, role: .additive)
        additive.additiveAmount = 12
        additive.additiveUnit = "g"
        additive.recipe = recipe
        ctx.insert(additive)

        let fragrance = RecipeIngredient(ingredient: lavender, percentage: 0, role: .fragrance)
        fragrance.additiveAmount = 100
        fragrance.additiveUnit = FragranceUnit.percentOfFragrances.rawValue
        fragrance.recipe = recipe
        ctx.insert(fragrance)

        let product = RecipeProduct(size: 120, unitSymbol: "g")
        product.recipe = recipe
        ctx.insert(product)

        try? ctx.save()
        return recipe
    }

    // MARK: - Naming

    @Test func copyName_NoExistingCopy_AppendsCopySuffix() {
        #expect(RecipeDuplicator.copyName(of: "Castile", among: []) == "Castile (copy)")
    }

    @Test func copyName_CopyAlreadyTaken_NumbersTheNext() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let existing = ["Castile", "Castile (copy)"].map { Recipe(name: $0) }
        existing.forEach { ctx.insert($0) }

        #expect(RecipeDuplicator.copyName(of: "Castile", among: existing) == "Castile (copy 2)")
    }

    @Test func copyName_SeveralCopiesTaken_SkipsToTheFirstFree() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let names = ["Castile", "Castile (copy)", "Castile (copy 2)", "Castile (copy 3)"]
        let existing = names.map { Recipe(name: $0) }
        existing.forEach { ctx.insert($0) }

        #expect(RecipeDuplicator.copyName(of: "Castile", among: existing) == "Castile (copy 4)")
    }

    /// Names are matched the way the rest of the app matches lookup names, so a
    /// differently-cased row still counts as taken.
    @Test func copyName_ExistingDiffersOnlyByCase_StillCountsAsTaken() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let existing = [Recipe(name: "CASTILE (COPY)")]
        existing.forEach { ctx.insert($0) }

        #expect(RecipeDuplicator.copyName(of: "Castile", among: existing) == "Castile (copy 2)")
    }

    // MARK: - Copying

    @Test func duplicate_CopiesEveryScalarField() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let copy = RecipeDuplicator.duplicate(recipe, among: [recipe], into: ctx)
        try ctx.save()

        #expect(copy.name == "Castile (copy)")
        #expect(copy.desc == "A gentle bar")
        #expect(copy.totalOilWeight == 1200)
        #expect(copy.superFat == 7)
        #expect(copy.waterParts == 2)
        #expect(copy.useCFM)
        #expect(copy.cfmNeutralizer == CFMNeutralizer.borax.rawValue)
        #expect(copy.fragranceUnit == FragranceUnit.percentOfFragrances.rawValue)
        #expect(copy.lyeIngredient?.name == "Sodium Hydroxide")
        #expect(copy.recipeKind == RecipeKind.soap.rawValue)
    }

    @Test func duplicate_NonSoapRecipe_CopyStaysNonSoap() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)
        recipe.recipeKind = RecipeKind.general.rawValue

        let copy = RecipeDuplicator.duplicate(recipe, among: [recipe], into: ctx)
        try ctx.save()

        #expect(copy.recipeKind == RecipeKind.general.rawValue)
    }

    @Test func duplicate_CopiesLineItemsAsNewRowsSharingTheIngredients() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let copy = RecipeDuplicator.duplicate(recipe, among: [recipe], into: ctx)
        try ctx.save()

        #expect(copy.ingredients.count == 4)
        #expect(recipe.ingredients.count == 4)
        // New line items, not the originals moved across.
        let sharedRows = Set(copy.ingredients.map(\.persistentModelID))
            .intersection(recipe.ingredients.map(\.persistentModelID))
        #expect(sharedRows.isEmpty)
        // The ingredients themselves are shared — inventory is not duplicated.
        #expect(Set(copy.ingredients.compactMap { $0.ingredient?.persistentModelID })
            == Set(recipe.ingredients.compactMap { $0.ingredient?.persistentModelID }))
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).count == 5)
    }

    @Test func duplicate_PreservesRolesAndAdditiveAmounts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let copy = RecipeDuplicator.duplicate(recipe, among: [recipe], into: ctx)
        try ctx.save()

        let oils = copy.ingredients.filter { $0.ingredientRole == .oil }
        #expect(Set(oils.map(\.percentage)) == [70, 30])
        let additive = try #require(copy.ingredients.first { $0.ingredientRole == .additive })
        #expect(additive.additiveAmount == 12)
        #expect(additive.additiveUnit == "g")
        #expect(copy.ingredients.count { $0.ingredientRole == .fragrance } == 1)
    }

    @Test func duplicate_CopiesProducts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let copy = RecipeDuplicator.duplicate(recipe, among: [recipe], into: ctx)
        try ctx.save()

        #expect(copy.products.count == 1)
        #expect(copy.products.first?.size == 120)
        #expect(recipe.products.count == 1)
    }

    @Test func duplicate_FilesTheCopyUnderTheSameCollections() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let copy = RecipeDuplicator.duplicate(recipe, among: [recipe], into: ctx)
        try ctx.save()

        #expect(copy.collections.map(\.name) == ["Gifts"])
        let gifts = try #require(try ctx.fetch(FetchDescriptor<RecipeCollection>()).first)
        #expect(gifts.recipes.count == 2)
    }

    /// A batch is a record of a run that happened, and it happened to the
    /// original — the copy has made nothing yet.
    @Test func duplicate_DoesNotCopyBatchHistory() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)
        let batch = Batch(recipe: recipe, recipeName: recipe.name, batchCount: 1, totalCost: 4)
        ctx.insert(batch)
        try ctx.save()

        let copy = RecipeDuplicator.duplicate(recipe, among: [recipe], into: ctx)
        try ctx.save()

        #expect(copy.batches.isEmpty)
        #expect(recipe.batches.count == 1)
        #expect(try ctx.fetch(FetchDescriptor<Batch>()).count == 1)
    }

    /// The pin lifts a row to the top of the list; two identical rows up there
    /// is not what "duplicate" should mean.
    @Test func duplicate_FavoriteRecipe_CopyStartsUnpinned() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)
        recipe.isFavorite = true
        try ctx.save()

        let copy = RecipeDuplicator.duplicate(recipe, among: [recipe], into: ctx)
        try ctx.save()

        #expect(copy.isFavorite == false)
        #expect(recipe.isFavorite)
    }

    @Test func duplicate_UnresolvedLineItem_IsCarriedOver() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)
        let orphan = RecipeIngredient(ingredient: nil, percentage: 30, role: .oil)
        orphan.recipe = recipe
        ctx.insert(orphan)
        try ctx.save()

        let copy = RecipeDuplicator.duplicate(recipe, among: [recipe], into: ctx)
        try ctx.save()

        #expect(copy.ingredients.count == 1)
        #expect(copy.ingredients.first?.ingredient == nil)
        #expect(copy.ingredients.first?.percentage == 30)
    }

    @Test func duplicate_EmptyRecipe_ProducesAnEmptyCopy() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Blank")
        ctx.insert(recipe)
        try ctx.save()

        let copy = RecipeDuplicator.duplicate(recipe, among: [recipe], into: ctx)
        try ctx.save()

        #expect(copy.name == "Blank (copy)")
        #expect(copy.ingredients.isEmpty)
        #expect(copy.products.isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Recipe>()).count == 2)
    }

    @Test func duplicate_TwiceInARow_ProducesTwoDistinctlyNamedCopies() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = seedRecipe(ctx)

        let first = RecipeDuplicator.duplicate(recipe, among: [recipe], into: ctx)
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<Recipe>())
        let second = RecipeDuplicator.duplicate(recipe, among: all, into: ctx)
        try ctx.save()

        #expect(first.name == "Castile (copy)")
        #expect(second.name == "Castile (copy 2)")
        #expect(try ctx.fetch(FetchDescriptor<Recipe>()).count == 3)
    }
}
