import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class FormulaListViewModel {
    var showingAddFormula: Bool = false
    var editMode: EditMode = .inactive
    var selection: Set<PersistentIdentifier> = []
    var confirmingDelete: [Formula] = []
    var searchText: String = ""

    func filtered(_ formulas: [Formula]) -> [Formula] {
        guard !searchText.isEmpty else { return formulas }
        return formulas.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    func delete(_ formula: Formula, context: ModelContext) {
        if formula.ingredients.isEmpty && formula.variants.isEmpty && formula.runs.isEmpty {
            context.delete(formula)
        } else {
            confirmingDelete = [formula]
        }
    }

    func deleteSelected(in formulas: [Formula], context: ModelContext) {
        let targets = selection.compactMap { id in formulas.first { $0.persistentModelID == id } }
        let hasChildren = targets.contains {
            !$0.ingredients.isEmpty || !$0.variants.isEmpty || !$0.runs.isEmpty
        }
        if hasChildren {
            confirmingDelete = targets
        } else {
            targets.forEach { context.delete($0) }
            selection.removeAll()
            editMode = .inactive
        }
    }

    func confirmDelete(context: ModelContext) {
        confirmingDelete.forEach { context.delete($0) }
        confirmingDelete = []
        selection.removeAll()
        editMode = .inactive
    }
}
