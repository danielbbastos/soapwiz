import Foundation
import OSLog

/// The ingredients SoapWiz ships with, read from `IngredientLibrary.json` in the
/// app bundle.
struct IngredientLibrary {
    private static let log = Logger(subsystem: "pt.daphnia.SoapWiz", category: "library")

    let entries: [IngredientLibraryEntry]

    static let bundled = load(from: .main)

    /// The name each entry ships under, keyed by slug. Built once: the merge
    /// asks per row, and the catalog runs to hundreds of entries.
    static let bundledNamesBySlug: [String: String] = Dictionary(
        bundled.entries.map { ($0.slug, $0.name) },
        uniquingKeysWith: { first, _ in first }
    )

    /// The name the catalog ships for `slug`, or `nil` when it ships no such
    /// entry — a row with no slug, one installed by a build whose catalog has
    /// since changed, or a catalog that failed to load. Callers treat `nil` as
    /// "can't tell", never as "not renamed".
    static func bundledName(for slug: String) -> String? {
        guard !slug.isEmpty else { return nil }
        return bundledNamesBySlug[slug]
    }

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
