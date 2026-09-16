import Foundation
import SwiftData

/// One entry in the import queue: the ingredient as captured when the flow
/// opened, alongside the two values that have to be read while the row is
/// certainly still in the store.
///
/// The queue is walked one entry at a time, so an entry can sit here for minutes
/// before it is reached, and the duplicate merge can delete it in the meantime.
/// By then the reference is detached and reading a stored attribute off it traps
/// — so the slug needed to find the survivor, and the name the flow displays,
/// are taken up front. See `LiveIngredient`.
private struct QueuedIngredient {
    let ingredient: Ingredient
    let slug: String
    let name: String
}

/// Drives the sequential bulk-import flow: walks an ordered queue of ingredients,
/// presenting a purchase form for each one in turn. Shared fields (provider,
/// purchase date) carry over from each committed entry to the next to cut
/// repetition across a single purchase order. The journal code does not: it is
/// numbered per ingredient, so each form derives its own.
@MainActor
@Observable
final class BulkImportFlowViewModel {
    private(set) var index: Int = 0
    private(set) var currentForm: PurchaseFormViewModel

    private let queue: [QueuedIngredient]

    /// Values carried forward to pre-fill the next entry in the queue.
    private var carriedProvider: Provider?
    private var carriedDate: Date = Date()

    init(ingredients: [Ingredient]) {
        precondition(!ingredients.isEmpty, "Bulk import requires at least one ingredient")
        queue = ingredients.map {
            QueuedIngredient(ingredient: $0, slug: $0.librarySlug, name: $0.name)
        }
        // The first entry is opened immediately, while every row in the queue is
        // still the one the picker just handed over.
        currentForm = PurchaseFormViewModel(ingredient: ingredients[0])
    }

    /// Index clamped to the last valid entry. After the final step `index` runs one
    /// past the end (driving `isComplete`); the view still re-renders once before it
    /// dismisses, so display accessors must stay in bounds.
    private var displayIndex: Int { min(index, queue.count - 1) }

    var total: Int { queue.count }
    /// 1-based position of the current ingredient in the queue.
    var position: Int { displayIndex + 1 }
    var progressText: String { "\(position) of \(total)" }

    /// The current ingredient's name as it read when the flow opened, rather than
    /// off the row itself: the entry may since have been merged away, and reading
    /// `name` off the detached reference would trap. It is also the name the user
    /// picked, so it is the honest label either way.
    var currentIngredientName: String { queue[displayIndex].name }

    var isLastStep: Bool { index == queue.count - 1 }
    /// True once every ingredient in the queue has been handled.
    var isComplete: Bool { index >= queue.count }
    var canCommit: Bool { currentForm.isValid }

    /// Persists the current entry, captures its shared fields for carry-over, and advances.
    ///
    /// Throws without advancing when the ingredient has been merged away while the
    /// flow was open: the queue stays where it is and what the user typed is still
    /// on screen, so the entry can be retried or skipped rather than disappearing
    /// along with the step.
    func commitAndAdvance(context: ModelContext) throws {
        try currentForm.save(context: context)
        carriedProvider = currentForm.selectedProvider
        carriedDate = currentForm.dateOfPurchase
        advance(context: context)
    }

    /// Skips the current ingredient without recording a purchase.
    func skip(context: ModelContext) {
        advance(context: context)
    }

    /// Moves to the next entry whose ingredient is still in the store.
    ///
    /// An entry the merge deleted is passed over rather than presented:
    /// `PurchaseFormViewModel.init` reads the row's slug, which traps on a
    /// detached reference, and a purchase written against one would be lost to
    /// the cascade on `Ingredient.purchases` anyway. Resolving by slug lands on
    /// the survivor whenever there is one, so this passes over only entries that
    /// could not have been saved under any spelling.
    private func advance(context: ModelContext) {
        index += 1
        while index < queue.count {
            let entry = queue[index]
            if let live = LiveIngredient.resolve(entry.ingredient, slug: entry.slug, in: context) {
                let form = PurchaseFormViewModel(ingredient: live)
                form.selectedProvider = carriedProvider
                form.dateOfPurchase = carriedDate
                currentForm = form
                return
            }
            index += 1
        }
    }
}
