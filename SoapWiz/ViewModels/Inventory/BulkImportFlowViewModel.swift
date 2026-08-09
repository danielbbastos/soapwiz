import Foundation
import SwiftData

/// Drives the sequential bulk-import flow: walks an ordered queue of ingredients,
/// presenting a purchase form for each one in turn. Shared fields (provider,
/// purchase date) carry over from each committed entry to the next to cut
/// repetition across a single purchase order. The journal code does not: it is
/// numbered per ingredient, so each form derives its own.
@MainActor
@Observable
final class BulkImportFlowViewModel {
    let ingredients: [Ingredient]
    private(set) var index: Int = 0
    private(set) var currentForm: PurchaseFormViewModel

    /// Values carried forward to pre-fill the next entry in the queue.
    private var carriedProvider: Provider?
    private var carriedDate: Date = Date()

    init(ingredients: [Ingredient]) {
        precondition(!ingredients.isEmpty, "Bulk import requires at least one ingredient")
        self.ingredients = ingredients
        currentForm = PurchaseFormViewModel(ingredient: ingredients[0])
    }

    /// Index clamped to the last valid entry. After the final step `index` runs one
    /// past the end (driving `isComplete`); the view still re-renders once before it
    /// dismisses, so display accessors must stay in bounds.
    private var displayIndex: Int { min(index, ingredients.count - 1) }

    var total: Int { ingredients.count }
    /// 1-based position of the current ingredient in the queue.
    var position: Int { displayIndex + 1 }
    var progressText: String { "\(position) of \(total)" }
    var currentIngredient: Ingredient { ingredients[displayIndex] }
    var isLastStep: Bool { index == ingredients.count - 1 }
    /// True once every ingredient in the queue has been handled.
    var isComplete: Bool { index >= ingredients.count }
    var canCommit: Bool { currentForm.isValid }

    /// Persists the current entry, captures its shared fields for carry-over, and advances.
    func commitAndAdvance(context: ModelContext) {
        currentForm.save(context: context)
        carriedProvider = currentForm.selectedProvider
        carriedDate = currentForm.dateOfPurchase
        advance()
    }

    /// Skips the current ingredient without recording a purchase.
    func skip() {
        advance()
    }

    private func advance() {
        index += 1
        guard index < ingredients.count else { return }
        let form = PurchaseFormViewModel(ingredient: ingredients[index])
        form.selectedProvider = carriedProvider
        form.dateOfPurchase = carriedDate
        currentForm = form
    }
}
