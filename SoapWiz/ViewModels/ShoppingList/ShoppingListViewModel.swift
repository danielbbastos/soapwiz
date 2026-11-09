import Foundation
import SwiftData

@MainActor
@Observable
final class ShoppingListViewModel {
    private let modelContext: ModelContext
    private let now: () -> Date

    init(modelContext: ModelContext, now: @escaping () -> Date = { .now }) {
        self.modelContext = modelContext
        self.now = now
    }

    /// Ingredients already on the list, checked or not, are left out: ticking an
    /// item off must not bring its suggestion straight back.
    func suggestions(
        items: [ShoppingListItem],
        ingredients: [Ingredient],
        purchases: [IngredientPurchase],
        tracksInventory: Bool
    ) -> [ShoppingSuggestion] {
        ShoppingSuggestions.make(
            ingredients: ingredients,
            purchases: purchases,
            listedIngredientIDs: Set(items.compactMap { $0.ingredient?.persistentModelID }),
            tracksInventory: tracksInventory,
            now: now()
        )
    }

    func add(_ suggestion: ShoppingSuggestion) {
        addAll([suggestion])
    }

    func addAll(_ suggestions: [ShoppingSuggestion]) {
        for suggestion in suggestions {
            let ingredient = suggestion.ingredient
            modelContext.insert(ShoppingListItem(name: ingredient.name, unit: ingredient.unit, ingredient: ingredient))
        }
        modelContext.saveLoggingFailure()
    }

    func addPlanned(_ lines: [ShoppingListPlannedLine]) {
        guard !lines.isEmpty else { return }
        for line in lines {
            if let target = line.mergeTarget {
                target.amount = (target.amount ?? 0) + line.amount
                target.note = line.note
            } else {
                modelContext.insert(
                    ShoppingListItem(
                        name: line.ingredient.name,
                        amount: line.amount,
                        unit: line.unit,
                        ingredient: line.ingredient,
                        note: line.note
                    )
                )
            }
        }
        modelContext.saveLoggingFailure()
    }

    func addItem(name: String, amount: Double?, unit: String, ingredient: Ingredient?, note: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        modelContext.insert(
            ShoppingListItem(
                name: trimmedName,
                amount: amount,
                unit: unit,
                ingredient: ingredient,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        modelContext.saveLoggingFailure()
    }

    // swiftlint:disable:next function_parameter_count
    func update(_ item: ShoppingListItem, name: String, amount: Double?, unit: String, ingredient: Ingredient?, note: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        item.name = trimmedName
        item.amount = amount
        item.unit = unit
        if item.ingredient?.persistentModelID != ingredient?.persistentModelID {
            // A linked line counts as bought once a later purchase exists, so a new link starts the line afresh.
            item.createdAt = now()
        }
        item.ingredient = ingredient
        item.ingredientSlug = ingredient?.librarySlug ?? ""
        item.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.saveLoggingFailure()
    }

    /// Only a ticked line tied to an ingredient and not yet bought can take a purchase from the list.
    func offersAddPurchase(_ item: ShoppingListItem, boughtDate: Date?) -> Bool {
        item.isChecked && boughtDate == nil && item.ingredient != nil
    }

    func purchasePrefill(for item: ShoppingListItem, purchases: [IngredientPurchase]) -> PurchasePrefill? {
        guard let ingredient = item.ingredient else { return nil }
        let provider = LastPurchase.newestPurchases(in: purchases)[ingredient.persistentModelID]?.provider
        let quantity = item.amount.flatMap { $0 > 0 && item.unit == ingredient.unit ? $0 : nil }
        return PurchasePrefill(provider: provider, quantity: quantity)
    }

    func toggle(_ item: ShoppingListItem) {
        item.isChecked.toggle()
        item.checkedAt = item.isChecked ? now() : nil
        modelContext.saveLoggingFailure()
    }

    func delete(_ item: ShoppingListItem) {
        removeAll([item])
    }

    func clearChecked(in items: [ShoppingListItem], boughtDates: [PersistentIdentifier: Date] = [:]) {
        removeAll(items.filter { $0.isChecked || boughtDates[$0.persistentModelID] != nil })
    }

    func removeAll(_ items: [ShoppingListItem]) {
        for item in items {
            modelContext.delete(item)
        }
        modelContext.saveLoggingFailure()
    }

    func dismiss(_ suggestion: ShoppingSuggestion) {
        suggestion.ingredient.shoppingSuggestionDismissedAt = now()
        modelContext.saveLoggingFailure()
    }
}
