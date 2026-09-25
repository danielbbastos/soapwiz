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
    /// Off turns SoapWiz into a formulation tool: batches skip the stock check
    /// and the deduction, stock and expiry warnings go quiet, and cost UI is
    /// hidden. Purchases are left untouched, so switching back on is lossless.
    var tracksInventory: Bool = true
    /// The ISO code prices are shown in. Prices are stored as bare numbers, so
    /// the currency is a setting of the data rather than of the device: two
    /// devices in different regions must label the same prices alike. Empty
    /// until the user picks one, and until then the region's currency is shown
    /// — a region default is never stored, so it can't outrank another
    /// device's real choice when duplicate settings rows merge.
    var currencyCode: String = ""

    init() {}

    /// The settings record to read and write, chosen deterministically so every
    /// caller agrees even while duplicates are still present. Pure — it never
    /// inserts or deletes, so read paths such as `BackupService.makeBackup` can
    /// call it safely. Collapsing duplicates is `DuplicateMerger`'s job.
    static func canonical(from records: [AppSettings]) -> AppSettings? {
        records.min { $0.uuid.uuidString < $1.uuid.uuidString }
    }

    /// The tracking setting as views read it from a `@Query`: tracked until a
    /// settings record says otherwise, matching the stored default.
    static func tracksInventory(from records: [AppSettings]) -> Bool {
        canonical(from: records)?.tracksInventory ?? true
    }

    /// The currency prices are shown in, as views read it from a `@Query`.
    static func currencyCode(from records: [AppSettings], locale: Locale = .autoupdatingCurrent) -> String {
        let chosen = canonical(from: records)?.currencyCode ?? ""
        return chosen.isEmpty ? regionCurrencyCode(locale: locale) : chosen
    }

    /// The region's currency, or the euro for a region without one.
    static func regionCurrencyCode(locale: Locale = .autoupdatingCurrent) -> String {
        locale.currency?.identifier ?? "EUR"
    }

    static func resolve(in context: ModelContext) -> AppSettings {
        let existing = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        if let settings = canonical(from: existing) { return settings }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }
}
