#if DEBUG
import CoreData
import Foundation
import SwiftData

/// Pushes every record type and field to the CloudKit **Development**
/// environment, so the schema can then be deployed to Production from the
/// CloudKit Console.
///
/// SwiftData's mirroring only creates record types lazily, for records it
/// actually exports — an attribute that has never held a value on any device
/// never reaches the Development schema, and a Production deploy made without
/// it breaks sync the first time a user sets that field. Core Data's
/// `initializeCloudKitSchema()` creates them all up front; this is Apple's
/// documented route to it from SwiftData.
///
/// Opt-in via a launch argument, run once on a device or simulator signed in
/// to iCloud, before the store opens. Debug builds only: Release builds talk to
/// Production, where the schema must never be written this way.
enum CloudKitSchemaInitializer {
    static let launchArgument = "-SoapWizInitializeCloudKitSchema"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func run(storeURL: URL) throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: ModelContainerFactory.modelTypes) else {
            throw CloudKitSchemaInitializerError.modelUnavailable
        }
        try autoreleasepool {
            let description = NSPersistentStoreDescription(url: storeURL)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: ModelContainerFactory.cloudKitContainerIdentifier
            )
            description.shouldAddStoreAsynchronously = false

            let container = NSPersistentCloudKitContainer(name: "SoapWiz", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            var loadError: (any Error)?
            container.loadPersistentStores { _, error in
                loadError = error
            }
            if let loadError { throw loadError }

            try container.initializeCloudKitSchema()

            // The SwiftData container opens the same file next; leaving this
            // coordinator attached would hold it open twice.
            let coordinator = container.persistentStoreCoordinator
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        }
    }
}

enum CloudKitSchemaInitializerError: Error {
    case modelUnavailable
}
#endif
