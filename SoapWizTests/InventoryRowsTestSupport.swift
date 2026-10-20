import Foundation
import SwiftData
@testable import SoapWiz

/// What the `InventoryRows` suites share.
@MainActor
protocol InventoryRowsTestHelpers {}

extension InventoryRowsTestHelpers {
    func makeContainer() throws -> ModelContainer {
        let schema = ModelContainerFactory.schema
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
    }

    func makePurchase(quantity: Double = 100) -> IngredientPurchase {
        IngredientPurchase(
            dateOfPurchase: .now,
            quantity: quantity,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
    }

    /// Waits for `condition`, which a background task makes true, for at most
    /// two seconds.
    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Counts the fetches the inventory makes.
@MainActor
final class InventoryFetchCounter {
    private(set) var count = 0

    func fetch(_ context: ModelContext) throws -> InventoryRows.FetchedRows {
        count += 1
        return try InventoryRows.fetchAll(in: context)
    }
}
