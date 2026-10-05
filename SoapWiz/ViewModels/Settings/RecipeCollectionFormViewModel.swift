import Foundation
import SwiftData

@MainActor
@Observable
final class RecipeCollectionFormViewModel {
    var name: String = ""
    var color: CollectionColor = .neutral

    let collection: RecipeCollection?
    private let initialName: String
    private let initialColor: CollectionColor

    init(collection: RecipeCollection? = nil) {
        self.collection = collection
        initialName = collection?.name ?? ""
        initialColor = collection?.color ?? .neutral
        name = initialName
        color = initialColor
    }

    var isEditing: Bool { collection != nil }
    /// Whether anything was changed, which stops a swipe from closing the sheet.
    var isDirty: Bool { name != initialName || color != initialColor }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    func isDuplicate(among collections: [RecipeCollection]) -> Bool {
        guard !trimmedName.isEmpty else { return false }
        return collections.contains { $0.name.lookupKey == trimmedName.lookupKey && $0 != collection }
    }

    func isValid(among collections: [RecipeCollection]) -> Bool {
        !trimmedName.isEmpty && !isDuplicate(among: collections)
    }

    @discardableResult
    func save(context: ModelContext) -> RecipeCollection {
        if let collection {
            collection.name = trimmedName
            collection.colorName = color.rawValue
            return collection
        }
        let newCollection = RecipeCollection(name: trimmedName, colorName: color.rawValue)
        context.insert(newCollection)
        return newCollection
    }
}
