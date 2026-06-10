import Foundation
import SwiftData

/// One row of usage history: a batch consuming an amount of an ingredient, or
/// drawing it from one specific purchase. Built from the immutable
/// `BatchLineItem` snapshots — nothing here recomputes against live data.
struct UsageEntry: Identifiable {
    struct ID: Hashable {
        let lineItem: PersistentIdentifier
        /// Index into the line item's `draws` for purchase-scoped entries;
        /// `nil` for ingredient-scoped entries (one per line item).
        let drawIndex: Int?
    }

    let id: ID
    /// The batch that made the deduction; tapping the row opens its detail.
    let batch: Batch
    let date: Date
    /// Amount deducted, in the ingredient's inventory unit.
    let amount: Double
    let unit: String
    /// Labels of the purchases the amount was drawn from (lot badge or journal
    /// code). Empty on purchase-scoped entries, where the purchase is implied.
    let sourceLabels: [String]
}

enum UsageHistory {
    /// Every batch consumption of `ingredient`, newest first.
    static func entries(for ingredient: Ingredient) -> [UsageEntry] {
        ingredient.batchLineItems.compactMap { item -> UsageEntry? in
            guard let batch = item.batch else { return nil }
            return UsageEntry(
                id: .init(lineItem: item.persistentModelID, drawIndex: nil),
                batch: batch,
                date: batch.dateCreated,
                amount: item.amountConsumed,
                unit: item.unit,
                sourceLabels: item.draws.map { sourceLabel(for: $0, in: ingredient) }
            )
        }
        .sorted { $0.date > $1.date }
    }

    /// Every deduction batches made against `purchase`, newest first.
    static func entries(for purchase: IngredientPurchase) -> [UsageEntry] {
        guard let ingredient = purchase.ingredient else { return [] }
        return ingredient.batchLineItems.flatMap { item -> [UsageEntry] in
            guard let batch = item.batch else { return [] }
            return item.draws.enumerated().compactMap { index, draw in
                guard draw.purchaseUUID == purchase.uuid else { return nil }
                return UsageEntry(
                    id: .init(lineItem: item.persistentModelID, drawIndex: index),
                    batch: batch,
                    date: batch.dateCreated,
                    amount: draw.amountDrawn,
                    unit: item.unit,
                    sourceLabels: []
                )
            }
        }
        .sorted { $0.date > $1.date }
    }

    /// Identifies the purchase a draw came from: its lot badge as snapshotted,
    /// falling back to the live purchase's journal code when the badge was
    /// empty. Wording matches `BatchDetailView`'s draw rows.
    private static func sourceLabel(for draw: BatchPurchaseDraw, in ingredient: Ingredient) -> String {
        if !draw.purchaseBadge.isEmpty { return "Lot \(draw.purchaseBadge)" }
        if let uuid = draw.purchaseUUID,
           let purchase = ingredient.purchases.first(where: { $0.uuid == uuid }),
           !purchase.journalCode.isEmpty {
            return "Journal \(purchase.journalCode)"
        }
        return "No lot"
    }
}
