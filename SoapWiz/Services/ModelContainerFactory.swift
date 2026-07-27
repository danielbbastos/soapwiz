import Foundation
import SwiftData

/// Builds the app's `ModelContainer`. Mirroring to CloudKit is best-effort: a
/// device with no iCloud account, no entitlement, or an unreachable container
/// must still get a fully working local store rather than a failed launch.
enum ModelContainerFactory {
    static let cloudKitContainerIdentifier = "iCloud.pt.daphnia.SoapWiz"

    static let schema = Schema([
        Ingredient.self,
        IngredientPurchase.self,
        IngredientCategory.self,
        StorageLocation.self,
        Provider.self,
        Recipe.self,
        RecipeIngredient.self,
        RecipeProduct.self,
        Batch.self,
        BatchLineItem.self,
        AppSettings.self
    ])

    /// Tries CloudKit-mirrored storage, then plain local storage. In DEBUG a
    /// third attempt wipes the store first, since a schema change during
    /// development leaves an incompatible file behind. That wipe never runs in
    /// release builds — the store may hold the user's only copy of data that
    /// has not finished syncing.
    static func makeProduction() -> ModelContainer {
        let mirrored = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        if let container = try? ModelContainer(for: schema, configurations: [mirrored]) {
            return container
        }

        // `.none` is required, not merely explicit: the default is `.automatic`,
        // which turns mirroring back on whenever the iCloud entitlement is
        // present — so the fallback would fail for the same reason as the
        // attempt it is meant to rescue.
        let local = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            #if DEBUG
            removeStore(at: local.url)
            do {
                return try ModelContainer(for: schema, configurations: [local])
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
            #else
            fatalError("Could not create ModelContainer: \(error)")
            #endif
        }
    }

    #if DEBUG
    private static func removeStore(at storeURL: URL) {
        let sidecars = ["shm", "wal"].map { storeURL.appendingPathExtension($0) }
        for url in [storeURL] + sidecars {
            try? FileManager.default.removeItem(at: url)
        }
    }
    #endif
}
