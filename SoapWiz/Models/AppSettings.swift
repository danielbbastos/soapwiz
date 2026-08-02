import Foundation
import SwiftData

@Model
final class AppSettings {
    /// Stable identity across devices. CloudKit cannot enforce uniqueness, so two
    /// devices can each create their own settings record; `uuid` is what lets every
    /// device agree on which one survives. See `DuplicateMerger`.
    var uuid: UUID = UUID()
    static let defaultPVPFactor: Double = 4.0

    var pvpFactor: Double = AppSettings.defaultPVPFactor
    var expiryNotificationsEnabled: Bool = false

    init() {}

    /// The settings record to read and write, chosen deterministically so every
    /// caller agrees even while duplicates are still present. Pure — it never
    /// inserts or deletes, so read paths such as `BackupService.makeBackup` can
    /// call it safely. Collapsing duplicates is `DuplicateMerger`'s job.
    static func canonical(from records: [AppSettings]) -> AppSettings? {
        records.min { $0.uuid.uuidString < $1.uuid.uuidString }
    }

    static func resolve(in context: ModelContext) -> AppSettings {
        let existing = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        if let settings = canonical(from: existing) { return settings }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }
}
