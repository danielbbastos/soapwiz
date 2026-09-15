import Foundation
import OSLog

/// The ingredients SoapWiz ships with, read from `IngredientLibrary.json` in the
/// app bundle.
struct IngredientLibrary {
    private static let log = Logger(subsystem: "pt.daphnia.SoapWiz", category: "library")

    let entries: [IngredientLibraryEntry]

    static let bundled = load(from: .main)

    /// An unreadable file yields an empty library rather than a failed launch:
    /// the user loses the built-in ingredients, not the app.
    static func load(from bundle: Bundle) -> IngredientLibrary {
        guard let url = bundle.url(forResource: "IngredientLibrary", withExtension: "json") else {
            log.error("IngredientLibrary.json is missing from the bundle.")
            return IngredientLibrary(entries: [])
        }
        do {
            let file = try JSONDecoder().decode(IngredientLibraryFile.self, from: Data(contentsOf: url))
            return IngredientLibrary(entries: file.entries)
        } catch {
            log.error("IngredientLibrary.json could not be read: \(error, privacy: .public)")
            return IngredientLibrary(entries: [])
        }
    }
}
