import Foundation
import SwiftData
@testable import SoapWiz

extension ModelConfiguration {
    /// In-memory store with mirroring explicitly disabled.
    ///
    /// `cloudKitDatabase` defaults to `.automatic`, which enables mirroring
    /// whenever the host app carries the iCloud entitlement. Tests must never
    /// reach CloudKit, so every test container goes through here.
    static func inMemory(_ schema: Schema) -> ModelConfiguration {
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    }
}
