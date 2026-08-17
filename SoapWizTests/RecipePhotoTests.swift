import Testing
import Foundation
import SwiftData
import UIKit
@testable import SoapWiz

// MARK: - Form

@Suite("Recipe photos", .serialized)
@MainActor
struct RecipePhotoTests: RecipeFormTestHelpers {

    @Test func save_WithAnImage_PopulatesBothTheImageAndTheThumbnail() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.name = "Castile"
        model.imageData = try #require(await ImageDownscaler.hero(from: makeImage()))

        let recipe = model.save(context: ctx)

        #expect(recipe.imageData == model.imageData)
        #expect(recipe.thumbnailData != nil)
    }

    /// The thumbnail exists so a list row doesn't carry the display image. A
    /// copy that isn't actually smaller would be pure overhead.
    @Test func save_WithAnImage_StoresAThumbnailSmallerThanTheImage() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.name = "Castile"
        model.imageData = try #require(await ImageDownscaler.hero(from: makeImage()))

        let recipe = model.save(context: ctx)

        let thumbnail = try #require(recipe.thumbnailData)
        let image = try #require(recipe.imageData)
        #expect(thumbnail.count < image.count)
    }

    @Test func save_ImageRemoved_ClearsBothAttributes() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try await photographedRecipe(ctx)
        let model = RecipeFormViewModel()
        model.load(from: recipe)

        model.imageData = nil
        model.save(context: ctx)

        #expect(recipe.imageData == nil)
        #expect(recipe.thumbnailData == nil)
    }

    /// A thumbnail left behind by a replaced photo would show one picture in the
    /// list and another on the detail screen.
    @Test func save_ImageReplaced_RegeneratesTheThumbnail() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try await photographedRecipe(ctx, fill: .systemOrange)
        let firstThumbnail = try #require(recipe.thumbnailData)
        let model = RecipeFormViewModel()
        model.load(from: recipe)

        model.imageData = try #require(await ImageDownscaler.hero(from: makeImage(fill: .systemTeal)))
        model.save(context: ctx)

        #expect(recipe.thumbnailData != firstThumbnail)
        #expect(recipe.thumbnailData == recipe.imageData.flatMap(ImageDownscaler.thumbnail(from:)))
    }

    /// Re-saving an untouched recipe must not rewrite the photo: the image lives
    /// in external storage, and rewriting it hands CloudKit an asset to
    /// re-upload for nothing.
    @Test func save_ImageUntouched_DoesNotRewriteTheStoredCopies() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try await photographedRecipe(ctx)
        // A sentinel rather than the real thumbnail: a save that rewrites the
        // pair when nothing changed is exactly what would replace it.
        let sentinel = Data("untouched".utf8)
        recipe.thumbnailData = sentinel
        let model = RecipeFormViewModel()
        model.load(from: recipe)

        model.desc = "Edited elsewhere"
        model.save(context: ctx)

        #expect(recipe.thumbnailData == sentinel)
    }

    @Test func load_RecipeWithAPhoto_FillsTheFormsImage() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try await photographedRecipe(ctx)

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.imageData == recipe.imageData)
    }

    @Test func load_RecipeWithoutAPhoto_LeavesTheFormsImageNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.imageData == nil)
    }

    // MARK: - Dirty state

    @Test func isDirty_PhotoAttached_IsTrue() async throws {
        let model = RecipeFormViewModel()
        model.name = "Castile"
        model.captureSnapshot()

        model.imageData = try #require(await ImageDownscaler.hero(from: makeImage()))

        #expect(model.isDirty)
    }

    @Test func isDirty_PhotoRemoved_IsTrue() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try await photographedRecipe(ctx)
        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.captureSnapshot()

        model.imageData = nil

        #expect(model.isDirty)
    }

    /// Opening a photographed recipe just to look at it must not count as work
    /// to lose, or Cancel starts asking about changes nobody made.
    @Test func isDirty_PhotoLoadedAndUntouched_IsFalse() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try await photographedRecipe(ctx)

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.captureSnapshot()

        #expect(!model.isDirty)
    }

    // MARK: - Duplication

    @Test func duplicate_RecipeWithAPhoto_CarriesBothCopies() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try await photographedRecipe(ctx)

        let copy = RecipeDuplicator.duplicate(recipe, among: [recipe], into: ctx)

        #expect(copy.imageData == recipe.imageData)
        #expect(copy.thumbnailData == recipe.thumbnailData)
    }

    @Test func duplicate_RecipeWithoutAPhoto_LeavesBothNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)

        let copy = RecipeDuplicator.duplicate(recipe, among: [recipe], into: ctx)

        #expect(copy.imageData == nil)
        #expect(copy.thumbnailData == nil)
    }

    // MARK: - Fixtures

    /// A stored recipe with both copies already populated, the way one saved
    /// through the form arrives.
    private func photographedRecipe(_ ctx: ModelContext, fill: UIColor = .systemOrange) async throws -> Recipe {
        let recipe = Recipe(name: "Castile")
        let image = try #require(await ImageDownscaler.hero(from: makeImage(fill: fill)))
        recipe.imageData = image
        recipe.thumbnailData = try #require(ImageDownscaler.thumbnail(from: image))
        ctx.insert(recipe)
        return recipe
    }
}

// MARK: - Fixtures

@MainActor
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
