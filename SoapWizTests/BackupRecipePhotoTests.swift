import Testing
import Foundation
import SwiftData
import UIKit
@testable import SoapWiz

/// Backup coverage for recipe photos, including a file written before recipes
/// could carry one.
@Suite("Backup – recipe photos", .serialized)
@MainActor
struct BackupRecipePhotoTests: BackupTestHelpers {

    @Test func roundTrip_PreservesTheRecipesPhoto() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        let image = try #require(ImageDownscaler.hero(from: makeImage()))
        try seededRecipe(ctx).imageData = image
        try ctx.save()

        try roundTripInPlace(ctx)

        let restored = try seededRecipe(ctx)
        #expect(restored.imageData == image)
    }

    /// The thumbnail is never written to the file — it is derivable, and
    /// carrying it would grow every export for nothing. Restore has to rebuild
    /// it, or a restored library shows placeholder rows for photographed recipes.
    @Test func roundTrip_RebuildsTheThumbnailFromTheRestoredPhoto() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        let image = try #require(ImageDownscaler.hero(from: makeImage()))
        try seededRecipe(ctx).imageData = image
        try ctx.save()

        try roundTripInPlace(ctx)

        let restored = try seededRecipe(ctx)
        let thumbnail = try #require(restored.thumbnailData)
        #expect(thumbnail == ImageDownscaler.thumbnail(from: image))
        #expect(thumbnail.count < image.count)
    }

    @Test func export_RecipePhoto_DoesNotWriteTheThumbnail() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        let recipe = try seededRecipe(ctx)
        recipe.imageData = try #require(ImageDownscaler.hero(from: makeImage()))
        recipe.thumbnailData = recipe.imageData.flatMap(ImageDownscaler.thumbnail(from:))
        try ctx.save()

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))

        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let recipes = try #require(json["recipes"] as? [[String: Any]])
        let exported = try #require(recipes.first)
        #expect(exported.keys.contains("imageData"))
        #expect(!exported.keys.contains("thumbnailData"))
    }

    @Test func roundTrip_RecipeWithoutAPhoto_StaysWithoutOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)

        try roundTripInPlace(ctx)

        let recipe = try seededRecipe(ctx)
        #expect(recipe.imageData == nil)
        #expect(recipe.thumbnailData == nil)
    }

    /// A file written before photos existed has no such key at all, and must
    /// still decode rather than being rejected as malformed.
    @Test func restore_BackupWrittenBeforePhotos_RestoresWithoutOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        try seededRecipe(ctx).imageData = try #require(ImageDownscaler.hero(from: makeImage()))
        try ctx.save()

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        let decoded = try BackupService.decode(try stripImageKey(from: data))
        #expect(decoded.recipes.first?.imageData == nil)

        try BackupService.restore(decoded, into: ctx)

        let recipe = try seededRecipe(ctx)
        #expect(recipe.name == "Castile")
        #expect(recipe.imageData == nil)
        #expect(recipe.thumbnailData == nil)
    }

    // MARK: - Helpers

    private func seededRecipe(_ ctx: ModelContext) throws -> Recipe {
        try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first)
    }

    /// Rewrites an exported file as the document it would have been before
    /// recipes could carry a photo: the key removed rather than nulled.
    private func stripImageKey(from data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        var json = try #require(object as? [String: Any])
        json["recipes"] = try #require(json["recipes"] as? [[String: Any]]).map { recipe in
            var recipe = recipe
            recipe.removeValue(forKey: "imageData")
            return recipe
        }
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func makeImage() -> UIImage {
        let size = CGSize(width: 1200, height: 900)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        }
    }
}
