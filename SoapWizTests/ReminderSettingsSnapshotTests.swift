import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Reminder settings snapshot")
@MainActor
struct ReminderSettingsSnapshotTests {

    private func makeRecord() -> AppSettings {
        let record = AppSettings()
        record.expiryNotificationsEnabled = false
        record.cureNotificationsEnabled = false
        record.tracksInventory = true
        return record
    }

    @Test func snapshot_SameSettings_AreEqual() {
        let record = makeRecord()

        #expect(ReminderSettingsSnapshot(settings: record) == ReminderSettingsSnapshot(settings: makeRecord()))
    }

    @Test func snapshot_ExpiryToggled_Differs() {
        let record = makeRecord()
        let before = ReminderSettingsSnapshot(settings: record)

        record.expiryNotificationsEnabled = true

        #expect(ReminderSettingsSnapshot(settings: record) != before)
    }

    @Test func snapshot_CureToggled_Differs() {
        let record = makeRecord()
        let before = ReminderSettingsSnapshot(settings: record)

        record.cureNotificationsEnabled = true

        #expect(ReminderSettingsSnapshot(settings: record) != before)
    }

    @Test func snapshot_TracksInventoryToggled_Differs() {
        let record = makeRecord()
        let before = ReminderSettingsSnapshot(settings: record)

        record.tracksInventory = false

        #expect(ReminderSettingsSnapshot(settings: record) != before)
    }

    @Test func snapshot_UnrelatedSettingsChanged_AreEqual() {
        let record = makeRecord()
        let before = ReminderSettingsSnapshot(settings: record)

        record.currencyCode = "GBP"
        record.pvpFactor += 1

        #expect(ReminderSettingsSnapshot(settings: record) == before)
    }

    @Test func snapshot_NoRecords_UsesStoredDefaults() {
        let snapshot = ReminderSettingsSnapshot(records: [])

        #expect(!snapshot.expiryNotificationsEnabled)
        #expect(!snapshot.cureNotificationsEnabled)
        #expect(snapshot.tracksInventory)
    }

    @Test func snapshot_Records_ReadsCanonicalRecord() {
        let low = AppSettings()
        low.uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
        low.cureNotificationsEnabled = true
        let high = AppSettings()
        high.uuid = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001") ?? UUID()

        let snapshot = ReminderSettingsSnapshot(records: [high, low])

        #expect(snapshot.cureNotificationsEnabled)
    }
}
