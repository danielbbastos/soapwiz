import Foundation
import OSLog
import SwiftData

/// Builds the app's `ModelContainer`. Mirroring to CloudKit is best-effort: a
/// device with no iCloud account, no entitlement, or an unreachable container
/// must still get a fully working local store rather than a failed launch.
enum ModelContainerFactory {
    /// The fallback is deliberately silent to the user but must not be silent to
    /// us: a schema CloudKit rejects looks exactly like a healthy local-only
    /// launch from the outside.
    private static let log = Logger(subsystem: "pt.daphnia.SoapWiz", category: "store")

    static let cloudKitContainerIdentifier = "iCloud.pt.daphnia.SoapWiz"

    /// Every model here obeys the constraints `NSPersistentCloudKitContainer`
    /// imposes on its automatic schema mapping: no unique constraints, no `.deny`
    /// delete rules, every attribute optional or defaulted, and every
    /// relationship optional with a declared inverse.
    ///
    /// To-many relationships are therefore stored as optional arrays under a
    /// `…Storage` suffix and exposed as non-optional computed accessors under the
    /// original names, so reads and writes elsewhere stay unaware of the
    /// optionality. Two consequences, both of which fail at fetch time rather
    /// than compile time:
    ///
    /// - The accessors are computed, so the store cannot resolve them. A
    ///   `#Predicate` referencing one fails the same way it would for any other
    ///   computed property.
    /// - The storage properties are optional to-many, which `#Predicate` cannot
    ///   filter on either: unwrapping puts a to-many key where the query needs a
    ///   single value, and it fails with "to-many key not allowed here". `??` and
    ///   `if let` do not rescue it — the problem is the shape, not the nil.
    ///
    /// To filter on a to-many, build the traversal as an `#Expression` over the
    /// storage property and evaluate it inside the predicate. See
    /// `CloudKitRelationshipTests.fetchFiltersOnToManyViaExpression`.
    static let schema = Schema([
        Ingredient.self,
        IngredientPurchase.self,
        IngredientCategory.self,
        StorageLocation.self,
        Provider.self,
        Recipe.self,
        RecipeIngredient.self,
        RecipeProduct.self,
        RecipeCollection.self,
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
        // `LOCAL_ONLY_STORE` is for builds signed without the iCloud
        // entitlement — a free personal team cannot carry that capability, and
        // asking for mirroring anyway is fatal rather than recoverable:
        // `ModelContainer(_:configurations:)` returns successfully, then
        // CloudKit traps on its own queue during asynchronous setup, long after
        // the `do`/`catch` below has been left. The only way to survive an
        // unentitled build is not to ask, and only the build knows.
        //
        // Deliberately set nowhere in `project.pbxproj`: every normal build
        // must compile the mirrored path unchanged. It is passed on the command
        // line, together with the stripped entitlements it has to travel with —
        // one without the other still crashes:
        //
        //     xcodebuild -project SoapWiz.xcodeproj -scheme SoapWiz \
        //       -configuration Debug -destination 'platform=iOS,name=<device>' \
        //       CODE_SIGN_ENTITLEMENTS=SoapWiz/SoapWiz-Local.entitlements \
        //       SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG LOCAL_ONLY_STORE' \
        //       -allowProvisioningUpdates build
        //
        // `DEBUG` has to be spelled out: the setting replaces the project's
        // value rather than adding to it, and dropping it silently removes
        // `DataSeeder` and the debug-only paths along with it.
        #if LOCAL_ONLY_STORE
        log.notice("Built without CloudKit; using a local store.")
        #else
        let mirrored = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [mirrored])
            log.notice("Store is CloudKit-mirrored.")
            return container
        } catch {
            log.error("CloudKit mirroring unavailable, falling back to a local store: \(error, privacy: .public)")
        }
        #endif

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
