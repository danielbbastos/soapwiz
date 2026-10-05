import Foundation
import SwiftData

@MainActor
@Observable
final class StorageLocationFormViewModel {
    var name: String = ""
    var locationDescription: String = ""

    let location: StorageLocation?
    private let initialName: String
    private let initialDescription: String

    init(location: StorageLocation? = nil) {
        self.location = location
        initialName = location?.name ?? ""
        initialDescription = location?.locationDescription ?? ""
        name = initialName
        locationDescription = initialDescription
    }

    var isEditing: Bool { location != nil }
    /// Whether anything was typed, which stops a swipe from closing the sheet.
    var isDirty: Bool { name != initialName || locationDescription != initialDescription }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var trimmedDescription: String { locationDescription.trimmingCharacters(in: .whitespaces) }

    func isDuplicate(among locations: [StorageLocation]) -> Bool {
        guard !trimmedName.isEmpty else { return false }
        return locations.contains { $0.name.lookupKey == trimmedName.lookupKey && $0 != location }
    }

    func isValid(among locations: [StorageLocation]) -> Bool {
        !trimmedName.isEmpty && !isDuplicate(among: locations)
    }

    @discardableResult
    func save(context: ModelContext) -> StorageLocation {
        if let location {
            location.name = trimmedName
            location.locationDescription = trimmedDescription
            return location
        }
        let newLocation = StorageLocation(name: trimmedName, locationDescription: trimmedDescription)
        context.insert(newLocation)
        return newLocation
    }
}
