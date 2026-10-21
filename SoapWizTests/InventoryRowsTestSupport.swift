import Foundation
import SwiftData
import Testing
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

    var importStart: SyncEvent {
        SyncEvent(kind: .import, endDate: nil, succeeded: false, error: nil)
    }

    var importEnd: SyncEvent {
        SyncEvent(kind: .import, endDate: .now, succeeded: true, error: nil)
    }

    /// A first-import record on its own defaults, so a test that finishes an
    /// import never marks the real device as having synced.
    func isolatedFirstImport() throws -> FirstImportRecord {
        let defaults = try #require(UserDefaults(suiteName: "pt.tachyon.SoapWiz.tests.\(UUID().uuidString)"))
        return FirstImportRecord(defaults: defaults)
    }

    /// A sync status store on its own defaults, for the same reason.
    func isolatedSyncStatus() throws -> SyncStatusStore {
        let defaults = try #require(UserDefaults(suiteName: "pt.tachyon.SoapWiz.tests.\(UUID().uuidString)"))
        return SyncStatusStore(defaults: defaults)
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
