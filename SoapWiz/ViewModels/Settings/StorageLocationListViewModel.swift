import Foundation
import SwiftData

@MainActor
@Observable
final class StorageLocationListViewModel {
    var showingAddLocation: Bool = false
    var locationToEdit: StorageLocation?
    var deleteBlockedLocation: StorageLocation?

    func delete(at offsets: IndexSet, in locations: [StorageLocation], context: ModelContext) {
        for index in offsets {
            let location = locations[index]
            if location.batches.isEmpty {
                context.delete(location)
            } else {
                deleteBlockedLocation = location
            }
        }
    }
}
