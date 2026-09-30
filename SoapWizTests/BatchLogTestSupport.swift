import Testing
import Foundation
import SwiftData
import UIKit
@testable import SoapWiz

/// Fixtures shared by the batch log suites.
@MainActor
enum BatchLogFixture {
    static func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    /// A whole-second date, so it survives the backup file's ISO 8601 encoding
    /// unchanged.
    static func date(day: Int) throws -> Date {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return try #require(Calendar.current.date(byAdding: .day, value: day, to: start))
    }

    /// A display-size photo, as the form would hand one over. Each colour
    /// encodes to different bytes, so photos can be told apart.
    static func photoData(_ color: UIColor = .systemOrange) async throws -> Data {
        let size = CGSize(width: 1200, height: 900)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        }
        return try #require(await ImageDownscaler.hero(from: image))
    }

    @discardableResult
    static func insertBatch(_ ctx: ModelContext, recipe: Recipe? = nil) -> Batch {
        let batch = Batch(recipe: recipe, recipeName: "Castile", batchCount: 1)
        ctx.insert(batch)
        return batch
    }

    @discardableResult
    static func insertEntry(
        _ ctx: ModelContext,
        batch: Batch,
        date: Date,
        text: String,
        photos: [Data] = []
    ) -> BatchLogEntry {
        let entry = BatchLogEntry(date: date, text: text)
        ctx.insert(entry)
        entry.batch = batch
        for (position, imageData) in photos.enumerated() {
            insertPhoto(ctx, entry: entry, imageData: imageData, position: position)
        }
        return entry
    }

    @discardableResult
    static func insertPhoto(
        _ ctx: ModelContext,
        entry: BatchLogEntry,
        imageData: Data?,
        position: Int
    ) -> BatchLogPhoto {
        let photo = BatchLogPhoto(imageData: imageData, position: position)
        ctx.insert(photo)
        photo.entry = entry
        return photo
    }
}

extension BatchLogEntryFormViewModel {
    /// Adds a photo with its thumbnail made here, as the photo field does off
    /// the main actor, so tests don't have to.
    func addPhoto(_ imageData: Data) {
        addPhoto(imageData, preview: ImageDownscaler.thumbnail(from: imageData))
    }
}
