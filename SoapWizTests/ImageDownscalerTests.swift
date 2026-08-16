import Testing
import UIKit
@testable import SoapWiz

@Suite("Image downscaler")
struct ImageDownscalerTests {

    // MARK: - Hero

    @Test func hero_ImageLargerThanTheLimit_FitsWithinIt() throws {
        let image = try #require(decode(ImageDownscaler.hero(from: makeImage(width: 3000, height: 2000))))
        #expect(max(image.size.width, image.size.height) == ImageDownscaler.heroMaxDimension)
    }

    @Test func hero_ImageLargerThanTheLimit_KeepsItsAspectRatio() throws {
        let image = try #require(decode(ImageDownscaler.hero(from: makeImage(width: 3000, height: 2000))))
        #expect(abs(image.size.width / image.size.height - 1.5) < 0.01)
    }

    /// Enlarging a small photo would cost bytes and add no detail, so the
    /// original dimensions survive untouched.
    @Test func hero_ImageSmallerThanTheLimit_IsNotUpscaled() throws {
        let image = try #require(decode(ImageDownscaler.hero(from: makeImage(width: 400, height: 300))))
        #expect(image.size == CGSize(width: 400, height: 300))
    }

    /// A photo taken with the phone rotated carries its rotation as metadata
    /// rather than in its pixels. Redrawing has to bake it in, or the stored
    /// image comes back on its side wherever the metadata isn't consulted.
    @Test func hero_ImageCarryingARotation_ComesBackUpright() throws {
        let landscape = makeImage(width: 400, height: 200)
        let cgImage = try #require(landscape.cgImage)
        let rotated = UIImage(cgImage: cgImage, scale: 1, orientation: .right)

        let image = try #require(decode(ImageDownscaler.hero(from: rotated)))

        #expect(image.size == CGSize(width: 200, height: 400))
        #expect(image.imageOrientation == .up)
    }

    @Test func hero_DataThatIsNotAnImage_ReturnsNil() {
        #expect(ImageDownscaler.hero(from: Data("not an image".utf8)) == nil)
    }

    // MARK: - Thumbnail

    @Test func thumbnail_ImageLargerThanTheLimit_FitsWithinIt() throws {
        let image = try #require(decode(ImageDownscaler.thumbnail(from: makeImage(width: 3000, height: 2000))))
        #expect(max(image.size.width, image.size.height) == ImageDownscaler.thumbnailMaxDimension)
    }

    /// The two sizes are derived from the same picture, so the one that goes in
    /// a list row has to be the smaller of them — that is the whole reason it
    /// exists.
    @Test func thumbnail_DerivedFromAHero_IsSmallerThanIt() throws {
        let source = makeImage(width: 3000, height: 2000)
        let hero = try #require(ImageDownscaler.hero(from: source))
        let thumbnail = try #require(ImageDownscaler.thumbnail(from: hero))

        let heroImage = try #require(UIImage(data: hero))
        let thumbnailImage = try #require(UIImage(data: thumbnail))
        #expect(thumbnailImage.size.width < heroImage.size.width)
        #expect(thumbnail.count < hero.count)
    }

    @Test func thumbnail_ImageSmallerThanTheLimit_IsNotUpscaled() throws {
        let image = try #require(decode(ImageDownscaler.thumbnail(from: makeImage(width: 100, height: 50))))
        #expect(image.size == CGSize(width: 100, height: 50))
    }

    /// The nil path a caller relies on when a recipe has no photo: deriving a
    /// thumbnail from nothing yields nothing rather than an empty image.
    @Test func thumbnail_DataThatIsNotAnImage_ReturnsNil() {
        #expect(ImageDownscaler.thumbnail(from: Data("not an image".utf8)) == nil)
    }

    @Test func thumbnail_EmptyData_ReturnsNil() {
        #expect(ImageDownscaler.thumbnail(from: Data()) == nil)
    }

    // MARK: - Helpers

    /// Decoded at scale 1 by construction: `UIImage(data:)` never applies a
    /// screen scale, so `size` is the pixel size the downscaler produced.
    private func decode(_ data: Data?) -> UIImage? {
        data.flatMap(UIImage.init(data:))
    }

    /// Two flat blocks rather than one, so the JPEG encoder has something to
    /// spend bytes on — a single colour compresses to almost nothing at every
    /// size, which would make a size comparison meaningless.
    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        }
    }
}
