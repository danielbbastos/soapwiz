import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Whether a create/edit sheet holds changes, which is what stops a swipe or
/// an outside tap from closing it (SW-218).
@Suite("Form dirty state", .serialized)
@MainActor
struct FormDirtyStateTests: BatchProductionTestHelpers {

    // MARK: - Category

    @Test func category_New_Untouched_IsClean() {
        #expect(CategoryFormViewModel().isDirty == false)
    }

    @Test func category_New_NameTyped_IsDirty() {
        let model = CategoryFormViewModel()
        model.name = "Clays"
        #expect(model.isDirty)
    }

    @Test func category_Edit_Untouched_IsClean() {
        #expect(CategoryFormViewModel(category: IngredientCategory(name: "Clays")).isDirty == false)
    }

    @Test func category_Edit_NameChangedAndBack_IsClean() {
        let model = CategoryFormViewModel(category: IngredientCategory(name: "Clays"))
        model.name = "Clay"
        model.name = "Clays"
        #expect(model.isDirty == false)
    }

    // MARK: - Storage location

    @Test func storageLocation_New_Untouched_IsClean() {
        #expect(StorageLocationFormViewModel().isDirty == false)
    }

    @Test func storageLocation_Edit_DescriptionChanged_IsDirty() {
        let model = StorageLocationFormViewModel(location: StorageLocation(name: "Shelf", locationDescription: "Top"))
        #expect(model.isDirty == false)
        model.locationDescription = "Bottom"
        #expect(model.isDirty)
    }

    @Test func storageLocation_Edit_NameChanged_IsDirty() {
        let model = StorageLocationFormViewModel(location: StorageLocation(name: "Shelf"))
        model.name = "Cupboard"
        #expect(model.isDirty)
    }

    // MARK: - Provider

    @Test func provider_New_Untouched_IsClean() {
        #expect(ProviderFormViewModel().isDirty == false)
    }

    @Test func provider_Edit_EachFieldChanged_IsDirty() {
        let provider = Provider(name: "Soap Co", website: "https://soap.example", notes: "Fast")

        let name = ProviderFormViewModel(provider: provider)
        #expect(name.isDirty == false)
        name.name = "Soap Ltd"
        #expect(name.isDirty)

        let website = ProviderFormViewModel(provider: provider)
        website.website = "https://other.example"
        #expect(website.isDirty)

        let notes = ProviderFormViewModel(provider: provider)
        notes.notes = "Slow"
        #expect(notes.isDirty)
    }

    // MARK: - Recipe collection

    @Test func collection_New_Untouched_IsClean() {
        #expect(RecipeCollectionFormViewModel().isDirty == false)
    }

    @Test func collection_New_ColourPicked_IsDirty() {
        let model = RecipeCollectionFormViewModel()
        model.color = .green
        #expect(model.isDirty)
    }

    @Test func collection_Edit_Untouched_IsClean() {
        let collection = RecipeCollection(name: "Gifts", colorName: CollectionColor.red.rawValue)
        #expect(RecipeCollectionFormViewModel(collection: collection).isDirty == false)
    }

    @Test func collection_Edit_NameChanged_IsDirty() {
        let model = RecipeCollectionFormViewModel(collection: RecipeCollection(name: "Gifts"))
        model.name = "Presents"
        #expect(model.isDirty)
    }

    // MARK: - Create batch

    private func makeBatchModel(_ ctx: ModelContext) -> BatchProductionViewModel {
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)
        return BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: false)
    }

    @Test func createBatch_Untouched_HasNoChanges() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeBatchModel(ctx)

        #expect(model.hasChanges == false)
    }

    /// The suggested code is filled in for the user, not typed by them.
    @Test func createBatch_SuggestedCodeFilledIn_HasNoChanges() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeBatchModel(ctx)

        model.suggestCode(existingCodes: [])

        #expect(model.code.isEmpty == false)
        #expect(model.hasChanges == false)
    }

    @Test func createBatch_CodeTyped_HasChanges() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeBatchModel(ctx)
        model.suggestCode(existingCodes: [])

        model.code = "MY-CODE"

        #expect(model.hasChanges)
    }

    @Test func createBatch_CountChanged_HasChanges() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeBatchModel(ctx)

        model.batchCount = 2

        #expect(model.hasChanges)
    }

    @Test func createBatch_ProcessChanged_HasChanges() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeBatchModel(ctx)

        model.process = .hot

        #expect(model.hasChanges)
    }

    @Test func createBatch_CureLengthChosen_HasChanges() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeBatchModel(ctx)

        model.cureDays = 10

        #expect(model.hasChanges)
    }

    // MARK: - Recipe import

    @Test func recipeImport_Empty_HasNoChanges() {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: .mock()))
        #expect(model.hasChanges == false)
    }

    @Test func recipeImport_TextPasted_HasChanges() {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: .mock()))
        model.rawText = "Olive Oil 70%"
        #expect(model.hasChanges)
    }
}
