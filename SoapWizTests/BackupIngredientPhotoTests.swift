import Testing
import Foundation
import SwiftData
import UIKit
@testable import SoapWiz

/// Backup coverage for ingredient photos and avatar colours, including a file
/// written before ingredients could carry either.
@Suite("Backup – ingredient photos", .serialized)
@MainActor
struct BackupIngredientPhotoTests: BackupTestHelpers {

    @Test func roundTrip_PreservesTheIngredientsPhoto() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        let image = try #require(await ImageDownscaler.hero(from: makeImage()))
        try seededIngredient(ctx).imageData = image
        try ctx.save()

        try roundTripInPlace(ctx)

        #expect(try seededIngredient(ctx).imageData == image)
    }

    /// The thumbnail is never written to the file — it is derivable, and carrying
    /// it would grow every export for nothing. Restore has to rebuild it, or a
    /// restored library shows letter avatars for photographed ingredients.
    @Test func roundTrip_RebuildsTheThumbnailFromTheRestoredPhoto() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        let image = try #require(await ImageDownscaler.hero(from: makeImage()))
        try seededIngredient(ctx).imageData = image
        try ctx.save()

        try roundTripInPlace(ctx)

        let thumbnail = try #require(try seededIngredient(ctx).thumbnailData)
        #expect(thumbnail == ImageDownscaler.thumbnail(from: image))
        #expect(thumbnail.count < image.count)
    }

    @Test func export_IngredientPhoto_DoesNotWriteTheThumbnail() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        let ingredient = try seededIngredient(ctx)
        ingredient.imageData = try #require(await ImageDownscaler.hero(from: makeImage()))
        ingredient.thumbnailData = ingredient.imageData.flatMap(ImageDownscaler.thumbnail(from:))
        try ctx.save()

        let exported = try firstExportedIngredient(from: ctx)

        #expect(exported.keys.contains("imageData"))
        #expect(!exported.keys.contains("thumbnailData"))
    }

    @Test func roundTrip_IngredientWithoutAPhoto_StaysWithoutOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)

        try roundTripInPlace(ctx)

        let ingredient = try seededIngredient(ctx)
        #expect(ingredient.imageData == nil)
        #expect(ingredient.thumbnailData == nil)
    }

    /// A restored library has to look like the one that was backed up, which
    /// means the colours come back with it rather than being redrawn.
    @Test func roundTrip_PreservesTheAvatarColour() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        try seededIngredient(ctx).avatarColorName = AvatarColor.pink.rawValue
        try ctx.save()

        try roundTripInPlace(ctx)

        #expect(try seededIngredient(ctx).avatarColor == .pink)
    }

    /// A file written before either attribute existed has no such key at all, and
    /// must still decode rather than being rejected as malformed.
    @Test func restore_BackupWrittenBeforePhotos_RestoresWithoutOne() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        try seededIngredient(ctx).imageData = try #require(await ImageDownscaler.hero(from: makeImage()))
        try ctx.save()

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        let decoded = try BackupService.decode(try stripPhotoKeys(from: data))
        #expect(decoded.ingredients.first?.imageData == nil)
        #expect(decoded.ingredients.first?.avatarColorName == nil)

        try BackupService.restore(decoded, into: ctx)

        let ingredient = try seededIngredient(ctx)
        #expect(ingredient.name == "Olive Oil")
        #expect(ingredient.imageData == nil)
        #expect(ingredient.thumbnailData == nil)
    }

    /// The colour a pre-avatar file restores with is the random one drawn on the
    /// way in, not an empty string: an unphotographed row must never land in the
    /// list with no colour at all.
    @Test func restore_BackupWrittenBeforeAvatars_StillLandsWithAColour() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)

        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        try BackupService.restore(try BackupService.decode(try stripPhotoKeys(from: data)), into: ctx)

        #expect(AvatarColor(rawValue: try seededIngredient(ctx).avatarColorName) != nil)
    }

    // MARK: - Helpers

    private func seededIngredient(_ ctx: ModelContext) throws -> Ingredient {
        try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first)
    }

    private func firstExportedIngredient(from ctx: ModelContext) throws -> [String: Any] {
        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let ingredients = try #require(json["ingredients"] as? [[String: Any]])
        return try #require(ingredients.first)
    }

    /// Rewrites an exported file as the document it would have been before
    /// ingredients could carry a photo or a colour: the keys removed rather than
    /// nulled.
    private func stripPhotoKeys(from data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        var json = try #require(object as? [String: Any])
        json["ingredients"] = try #require(json["ingredients"] as? [[String: Any]]).map { ingredient in
            var ingredient = ingredient
            ingredient.removeValue(forKey: "imageData")
            ingredient.removeValue(forKey: "avatarColorName")
            return ingredient
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
