import Foundation

/// Filing the recipe under collections from the form's picker.
extension RecipeFormViewModel {
    func isSelected(_ collection: RecipeCollection) -> Bool {
        selectedCollections.contains { $0 === collection }
    }

    func toggleCollection(_ collection: RecipeCollection) {
        if let index = selectedCollections.firstIndex(where: { $0 === collection }) {
            selectedCollections.remove(at: index)
        } else {
            selectedCollections = (selectedCollections + [collection]).sortedByName
        }
    }

    /// What the picker row shows on the right. Spelled out for a single
    /// collection, counted beyond that — a row of names would overflow the
    /// narrow side of the form long before it stayed readable.
    var collectionsLabel: String {
        switch selectedCollections.count {
        case 0: "None"
        case 1: selectedCollections[0].name
        default: "\(selectedCollections.count) selected"
        }
    }
}
