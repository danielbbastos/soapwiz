import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// "Copy Recipe" pasted back into Import: read without the model, and landing
/// in the form as the recipe it was copied from.
@Suite("Recipe import of a SoapWiz copy", .serialized)
@MainActor
struct RecipeImportSoapWizCopyTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    /// A recipe with every setting the readable copy carries switched away from
    /// its default.
    private func makeRecipe(in context: ModelContext) throws -> Recipe {
        let recipe = Recipe.exportMock(in: context)
        recipe.useHybrid = true
        recipe.kohPercentage = 70
        recipe.naohPercentage = 30
        recipe.kohPurity = 85
        recipe.naohPurity = 97.5
        recipe.superFat = 8
        recipe.waterParts = 2.5
        recipe.useCFM = true
        recipe.cfmNeutralizer = CFMNeutralizer.borax.rawValue
        recipe.isCreamSoap = true
        recipe.fragrancePercentage = 5
        let gifts = RecipeCollection(name: "Gifts")
        context.insert(gifts)
        recipe.collections = [gifts]
        try context.save()
        return recipe
    }

    /// The recipe's "Copy Recipe" text, read through the import view model and
    /// reviewed against everything in the store.
    private func prepared(
        for recipe: Recipe,
        in context: ModelContext,
        collections: [RecipeCollection] = []
    ) async throws -> PreparedRecipeImport {
        let inventory = try context.fetch(FetchDescriptor<Ingredient>())
        let importer = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: .mock()))
        importer.rawText = RecipeTextExporter.text(for: recipe)
        await importer.extract(inventory: inventory, collections: collections)
        return try #require(importer.prepared)
    }

    @Test func extract_SoapWizCopy_ReachesReviewWithoutTheModel() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try makeRecipe(in: ctx)
        let inventory = try ctx.fetch(FetchDescriptor<Ingredient>())
        let stub = StubRecipeExtractor(draft: .mock())
        let model = RecipeImportViewModel(extractor: stub)
        model.rawText = RecipeTextExporter.text(for: recipe)

        #expect(model.textIsSoapWizCopy)
        await model.extract(inventory: inventory)

        #expect(stub.recorder.lastText == nil)
        #expect(model.phase == .review)
        #expect(model.unresolvedCount == 0)
        #expect(model.canConfirm)
    }

    @Test func extract_ForeignText_StillGoesToTheModel() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let stub = StubRecipeExtractor(draft: .mock())
        let model = RecipeImportViewModel(extractor: stub)
        model.rawText = "Olive Oil 70%\nCoconut Oil 30%"

        #expect(!model.textIsSoapWizCopy)
        await model.extract(inventory: [])

        #expect(stub.recorder.lastText != nil)
    }

    /// The acceptance test for the device report: every value the copy states
    /// comes back into the form as it was in the recipe.
    @Test func applyImport_SoapWizCopy_MatchesTheOriginalRecipe() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try makeRecipe(in: ctx)
        let collections = try ctx.fetch(FetchDescriptor<RecipeCollection>())
        let prepared = try await prepared(for: recipe, in: ctx, collections: collections)

        let imported = RecipeFormViewModel()
        imported.applyImport(prepared)
        let original = RecipeFormViewModel()
        original.load(from: recipe)

        #expect(imported.name == original.name)
        #expect(imported.desc == original.desc)
        #expect(imported.weightUnit == original.weightUnit)
        #expect(imported.totalOilWeight == original.totalOilWeight)
        #expect(imported.oilWeightUnit == original.oilWeightUnit)
        #expect(amounts(imported.oilDrafts.map { ($0.ingredient.name, $0.amount) })
            == amounts(original.oilDrafts.map { ($0.ingredient.name, $0.amount) }))
        #expect(imported.additiveDrafts.map(\.amount) == original.additiveDrafts.map(\.amount))
        #expect(imported.additiveDrafts.map(\.unit) == original.additiveDrafts.map(\.unit))
        #expect(imported.fragranceDrafts.map(\.amount) == original.fragranceDrafts.map(\.amount))
        #expect(imported.fragranceUnit == original.fragranceUnit)
        #expect(imported.fragrancePercentage == original.fragrancePercentage)
        #expect(imported.useHybrid == original.useHybrid)
        #expect(imported.kohPercentage == original.kohPercentage)
        #expect(imported.naohPercentage == original.naohPercentage)
        #expect(imported.kohPurity == original.kohPurity)
        #expect(imported.naohPurity == original.naohPurity)
        #expect(imported.recipeKind == original.recipeKind)
        #expect(imported.superFat == original.superFat)
        #expect(imported.waterParts == original.waterParts)
        #expect(imported.useCFM == original.useCFM)
        #expect(imported.cfmNeutralizer == original.cfmNeutralizer)
        #expect(imported.isCreamSoap == original.isCreamSoap)
        #expect(imported.selectedCollections.map(\.name) == original.selectedCollections.map(\.name))
    }

    @Test func applyImport_SingleLyeCopy_KeepsItsPurity() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)
        recipe.lyeType = "KOH"
        recipe.lyePurity = 85
        try ctx.save()
        let prepared = try await prepared(for: recipe, in: ctx)

        let imported = RecipeFormViewModel()
        imported.applyImport(prepared)

        #expect(imported.lyeType == "KOH")
        #expect(imported.lyePurity == 85)
    }

    @Test func applyImport_NonSoapCopy_OpensAsNonSoap() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.exportMock(in: ctx)
        recipe.recipeKind = RecipeKind.general.rawValue
        try ctx.save()
        let prepared = try await prepared(for: recipe, in: ctx)

        let imported = RecipeFormViewModel()
        imported.applyImport(prepared)
        let original = RecipeFormViewModel()
        original.load(from: recipe)

        #expect(imported.recipeKind == .general)
        #expect(imported.additiveDrafts.map(\.unit) == original.additiveDrafts.map(\.unit))
        #expect(imported.fragranceUnit == original.fragranceUnit)
    }

    @Test func prepared_CollectionTheUserDoesNotHave_IsDropped() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try makeRecipe(in: ctx)

        let prepared = try await prepared(for: recipe, in: ctx)

        #expect(prepared.draft.collectionNames == ["Gifts"])
        #expect(prepared.collections.isEmpty)
    }

    private func amounts(_ pairs: [(String, Double)]) -> [String: Double] {
        Dictionary(pairs, uniquingKeysWith: +)
    }
}
