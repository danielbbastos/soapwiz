import Foundation
import SwiftData

@MainActor
@Observable
final class QuantityUnitFormViewModel {
    var name: String = ""
    var symbol: String = ""

    let unit: QuantityUnit?

    init(unit: QuantityUnit? = nil) {
        self.unit = unit
        if let unit {
            name = unit.name
            symbol = unit.symbol
        }
    }

    var isEditing: Bool { unit != nil }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var trimmedSymbol: String { symbol.trimmingCharacters(in: .whitespaces) }

    func isDuplicateName(among units: [QuantityUnit]) -> Bool {
        guard !trimmedName.isEmpty else { return false }
        return units.contains { $0.name.lowercased() == trimmedName.lowercased() && $0 != unit }
    }

    func isDuplicateSymbol(among units: [QuantityUnit]) -> Bool {
        guard !trimmedSymbol.isEmpty else { return false }
        return units.contains { $0.symbol.lowercased() == trimmedSymbol.lowercased() && $0 != unit }
    }

    func isValid(among units: [QuantityUnit]) -> Bool {
        !trimmedName.isEmpty && !trimmedSymbol.isEmpty &&
        !isDuplicateName(among: units) && !isDuplicateSymbol(among: units)
    }

    func save(context: ModelContext) {
        if let unit {
            unit.name = trimmedName
            unit.symbol = trimmedSymbol
        } else {
            context.insert(QuantityUnit(name: trimmedName, symbol: trimmedSymbol))
        }
    }
}
