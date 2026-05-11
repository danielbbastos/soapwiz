import Foundation
import SwiftData

@MainActor
@Observable
final class QuantityUnitListViewModel {
    var showingAddUnit = false
    var unitToEdit: QuantityUnit?
    var deleteBlockedUnit: QuantityUnit?

    func delete(at offsets: IndexSet, in units: [QuantityUnit], context: ModelContext) {
        for index in offsets {
            let unit = units[index]
            if unit.ingredients.isEmpty {
                context.delete(unit)
            } else {
                deleteBlockedUnit = unit
            }
        }
    }
}
