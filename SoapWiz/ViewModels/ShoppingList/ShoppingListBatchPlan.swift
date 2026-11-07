import Foundation
import SwiftData

/// One ingredient a planned batch is short of, and where it goes on the list.
struct ShoppingListPlannedLine: Identifiable {
    let ingredient: Ingredient
    let amount: Double
    let unit: String
    /// The line already on the list that takes the amount, or `nil` for a new line.
    let mergeTarget: ShoppingListItem?
    /// The note the line carries once the plan is added.
    let note: String

    var id: PersistentIdentifier { ingredient.persistentModelID }
}

/// Turns the shortages of a batch that can't be made yet into shopping list lines.
enum ShoppingListBatchPlan {
    static func lines(
        shortages: [BatchRequirement],
        recipeName: String,
        batchCount: Int,
        items: [ShoppingListItem],
        boughtDates: [PersistentIdentifier: Date]
    ) -> [ShoppingListPlannedLine] {
        let label = "\(recipeName) \u{00D7}\(batchCount)"
        let planNote = newNote(label)
        return shortages.compactMap { requirement in
            let amount = roundedUp(requirement.shortfall, unit: requirement.unit)
            guard amount > 0 else { return nil }
            let ingredientID = requirement.ingredient.persistentModelID
            let target = items
                .filter {
                    !$0.isChecked
                        && boughtDates[$0.persistentModelID] == nil
                        && $0.ingredient?.persistentModelID == ingredientID
                        && $0.unit == requirement.unit
                }
                .min { $0.createdAt < $1.createdAt }
            return ShoppingListPlannedLine(
                ingredient: requirement.ingredient,
                amount: amount,
                unit: requirement.unit,
                mergeTarget: target,
                note: target.map { mergedNote(existing: $0.note, label: label) } ?? planNote
            )
        }
    }

    private static let coarseUnits: Set<String> = ["kg", "L", "lb"]
    private static let roundingTolerance = 1e-6

    /// Rounds a shortfall up so the list reads like something to buy: to a whole
    /// number, or to one decimal for units large enough that a whole one would
    /// overshoot (1.2 kg stays 1.2, not 2). The tolerance keeps floating point
    /// noise (480.0000001) from tipping an exact amount up a step.
    static func roundedUp(_ amount: Double, unit: String) -> Double {
        let step = coarseUnits.contains(unit) ? 10.0 : 1.0
        return (amount * step - roundingTolerance).rounded(.up) / step
    }

    private static func newNote(_ label: String) -> String {
        "For \(label)"
    }

    private static func mergedNote(existing: String, label: String) -> String {
        if existing.isEmpty { return newNote(label) }
        if existing.hasPrefix("For ") { return "\(existing), \(label)" }
        return "\(existing) \u{00B7} \(newNote(label))"
    }
}
