import Testing
import Foundation
import SwiftData
import UIKit
@testable import SoapWiz

@Suite("Ingredient photos", .serialized)
@MainActor
struct IngredientPhotoTests {

    // MARK: - Saving

    @Test func save_NewIngredientWithAnImage_PopulatesBothTheImageAndTheThumbnail() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeFormModel()
        model.imageData = try #require(await ImageDownscaler.hero(from: makeImage()))

        let ingredient = try #require(model.save(context: ctx))

        #expect(ingredient.imageData == model.imageData)
        #expect(ingredient.thumbnailData != nil)
    }

    /// The thumbnail exists so a list row doesn't carry the display image. A copy
    /// that isn't actually smaller would be pure overhead.
    @Test func save_WithAnImage_StoresAThumbnailSmallerThanTheImage() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeFormModel()
        model.imageData = try #require(await ImageDownscaler.hero(from: makeImage()))

        let ingredient = try #require(model.save(context: ctx))

        let thumbnail = try #require(ingredient.thumbnailData)
        let image = try #require(ingredient.imageData)
        #expect(thumbnail.count < image.count)
    }

    @Test func save_ImageRemoved_ClearsBothAttributes() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try await photographedIngredient(ctx)
        let model = IngredientFormViewModel(ingredient: ingredient)

        model.imageData = nil
        model.save(context: ctx)

        #expect(ingredient.imageData == nil)
        #expect(ingredient.thumbnailData == nil)
    }

    /// A thumbnail left behind by a replaced photo would show one picture in the
    /// list and another on the detail screen.
    @Test func save_ImageReplaced_RegeneratesTheThumbnail() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try await photographedIngredient(ctx, fill: .systemOrange)
        let firstThumbnail = try #require(ingredient.thumbnailData)
        let model = IngredientFormViewModel(ingredient: ingredient)

        model.imageData = try #require(await ImageDownscaler.hero(from: makeImage(fill: .systemTeal)))
        model.save(context: ctx)

        #expect(ingredient.thumbnailData != firstThumbnail)
        #expect(ingredient.thumbnailData == ingredient.imageData.flatMap(ImageDownscaler.thumbnail(from:)))
    }

    /// Re-saving an untouched ingredient must not rewrite the photo: the image
    /// lives in external storage, and rewriting it hands CloudKit an asset to
    /// re-upload for nothing.
    @Test func save_ImageUntouched_DoesNotRewriteTheStoredCopies() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try await photographedIngredient(ctx)
        // A sentinel rather than the real thumbnail: a save that rewrites the
        // pair when nothing changed is exactly what would replace it.
        let sentinel = Data("untouched".utf8)
        ingredient.thumbnailData = sentinel
        let model = IngredientFormViewModel(ingredient: ingredient)

        model.lowStockThreshold = "250"
        model.save(context: ctx)

        #expect(ingredient.thumbnailData == sentinel)
    }

    // MARK: - Loading

    @Test func init_IngredientWithAPhoto_FillsTheFormsImage() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try await photographedIngredient(ctx)

        let model = IngredientFormViewModel(ingredient: ingredient)

        #expect(model.imageData == ingredient.imageData)
    }

    @Test func init_IngredientWithoutAPhoto_LeavesTheFormsImageNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)

        let model = IngredientFormViewModel(ingredient: ingredient)

        #expect(model.imageData == nil)
    }

    // MARK: - Dirty state

    @Test func isDirty_PhotoAttached_IsTrue() async throws {
        let model = makeFormModel()
        model.captureSnapshot()

        model.imageData = try #require(await ImageDownscaler.hero(from: makeImage()))

        #expect(model.isDirty)
    }

    @Test func isDirty_PhotoRemoved_IsTrue() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try await photographedIngredient(ctx)
        let model = IngredientFormViewModel(ingredient: ingredient)
        model.captureSnapshot()

        model.imageData = nil

        #expect(model.isDirty)
    }

    /// Opening a photographed ingredient just to look at it must not count as
    /// work to lose, or Cancel starts asking about changes nobody made.
    @Test func isDirty_PhotoLoadedAndUntouched_IsFalse() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try await photographedIngredient(ctx)

        let model = IngredientFormViewModel(ingredient: ingredient)
        model.captureSnapshot()

        #expect(!model.isDirty)
    }

    // MARK: - Avatar colour

    /// The form previews the avatar while the user fills it in, so the colour it
    /// showed has to be the colour the saved row keeps — a new ingredient that
    /// changed colour the moment it was added would read as a bug.
    @Test func save_NewIngredient_KeepsTheColourTheFormPreviewed() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeFormModel()

        let ingredient = try #require(model.save(context: ctx))

        #expect(ingredient.avatarColor == model.avatarColor)
    }

    @Test func avatarColor_EditingAnIngredient_IsTheOneAlreadyStored() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.avatarColorName = AvatarColor.indigo.rawValue
        ctx.insert(ingredient)

        let model = IngredientFormViewModel(ingredient: ingredient)

        #expect(model.avatarColor == .indigo)
    }

    @Test func save_EditingAnIngredientsName_LeavesItsColourAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)
        let original = ingredient.avatarColorName
        let model = IngredientFormViewModel(ingredient: ingredient)

        model.name = "Extra Virgin Olive Oil"
        model.save(context: ctx)

        #expect(ingredient.avatarColorName == original)
    }

    /// An ingredient that predates avatars derives its colour from its name, so
    /// a rename would otherwise move it to a different one.
    @Test func save_RenamingAnIngredientWithNoStoredColour_KeepsTheColourItShowed() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.avatarColorName = ""
        ctx.insert(ingredient)
        let shown = ingredient.avatarColor
        let model = IngredientFormViewModel(ingredient: ingredient)

        model.name = "Extra Virgin Olive Oil"
        model.save(context: ctx)

        #expect(ingredient.avatarColor == shown)
        #expect(ingredient.avatarColorName == shown.rawValue)
    }

    /// Nothing else touches the colour: an ingredient only ever gets one, at
    /// creation or on that first save, and reading it never redraws.
    @Test func avatarColor_ReadRepeatedly_DoesNotChange() {
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")

        let colours = Set((0..<10).map { _ in ingredient.avatarColor })

        #expect(colours.count == 1)
    }

    @Test func avatarLetter_FormFollowsTheTypedName() {
        let model = IngredientFormViewModel()

        model.name = "  coconut oil"

        #expect(model.avatarLetter == "C")
    }

    @Test func avatarLetter_FormWithNoName_IsEmpty() {
        #expect(IngredientFormViewModel().avatarLetter.isEmpty)
    }

    // MARK: - Fixtures

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self,
            Recipe.self, RecipeIngredient.self, RecipeProduct.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    /// A form filled in far enough to save.
    private func makeFormModel() -> IngredientFormViewModel {
        let model = IngredientFormViewModel()
        model.name = "Olive Oil"
        model.selectedUnit = .grams
        return model
    }

    /// A stored ingredient with both copies already populated, the way one saved
    /// through the form arrives.
    private func photographedIngredient(_ ctx: ModelContext, fill: UIColor = .systemOrange) async throws -> Ingredient {
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        let image = try #require(await ImageDownscaler.hero(from: makeImage(fill: fill)))
        ingredient.imageData = image
        ingredient.thumbnailData = try #require(ImageDownscaler.thumbnail(from: image))
        ctx.insert(ingredient)
        return ingredient
    }

    private func makeImage(fill: UIColor = .systemOrange) -> UIImage {
        let size = CGSize(width: 1200, height: 900)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            fill.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        }
    }
}
