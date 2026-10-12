import Testing
import Foundation
import Observation
import SwiftData
@testable import SoapWiz

/// When the root settings refetch (SW-270). A second context stands in for
/// CloudKit: it writes to the same store without this context's `didSave`.
@Suite("Settings state", .serialized)
@MainActor
struct SettingsStateTests {

    private let locale = Locale(identifier: "en_GB")

    private func makeContainer() throws -> ModelContainer {
        let schema = ModelContainerFactory.schema
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
    }

    private func makeRecord(
        currencyCode: String = "USD",
        tracksInventory: Bool = false,
        in context: ModelContext
    ) throws -> AppSettings {
        let record = AppSettings()
        record.currencyCode = currencyCode
        record.tracksInventory = tracksInventory
        context.insert(record)
        try context.save()
        return record
    }

    /// Changes the settings record from a second context, as a CloudKit import would:
    /// written to the same store without this context's `didSave`.
    private func changeRemotely(in container: ModelContainer, _ change: (AppSettings) -> Void) throws {
        let other = ModelContext(container)
        let remote = try #require(try other.fetch(FetchDescriptor<AppSettings>()).first)
        change(remote)
        try other.save()
    }

    /// Whether `read` reported a change through observation by the time `act` returned.
    private func invalidates(reading read: @MainActor () -> Void, after act: @MainActor () throws -> Void) rethrows -> Bool {
        var changed = false
        withObservationTracking {
            read()
        } onChange: {
            changed = true
        }
        try act()
        return changed
    }

    // MARK: - Initial values

    @Test func init_NoRecord_UsesRegionCurrencyAndTracksInventory() throws {
        let container = try makeContainer()

        let sut = SettingsState(context: container.mainContext, locale: locale)

        #expect(sut.currencyCode == AppSettings.regionCurrencyCode(locale: locale))
        #expect(sut.tracksInventory)
    }

    @Test func init_RecordWithValues_LoadsThem() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try makeRecord(currencyCode: "USD", tracksInventory: false, in: context)

        let sut = SettingsState(context: context, locale: locale)

        #expect(sut.currencyCode == "USD")
        #expect(!sut.tracksInventory)
    }

    @Test func init_RecordWithEmptyCurrency_UsesRegionCurrency() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try makeRecord(currencyCode: "", in: context)

        let sut = SettingsState(context: context, locale: locale)

        #expect(sut.currencyCode == AppSettings.regionCurrencyCode(locale: locale))
    }

    // MARK: - Own saves

    @Test func save_ChangingCurrencyCode_Updates() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let record = try makeRecord(currencyCode: "USD", in: context)
        let sut = SettingsState(context: context, locale: locale)

        record.currencyCode = "GBP"
        try context.save()

        #expect(sut.currencyCode == "GBP")
    }

    @Test func save_ChangingTracksInventory_Updates() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let record = try makeRecord(tracksInventory: false, in: context)
        let sut = SettingsState(context: context, locale: locale)

        record.tracksInventory = true
        try context.save()

        #expect(sut.tracksInventory)
    }

    @Test func save_InsertingFirstRecord_Updates() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let sut = SettingsState(context: context, locale: locale)

        _ = try makeRecord(currencyCode: "USD", tracksInventory: false, in: context)

        #expect(sut.currencyCode == "USD")
        #expect(!sut.tracksInventory)
    }

    @Test func save_OnlyOtherEntity_DoesNotInvalidateOrRefetch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try makeRecord(currencyCode: "USD", in: context)
        let sut = SettingsState(context: context, locale: locale)
        try changeRemotely(in: container) { $0.currencyCode = "GBP" }

        let invalidated = try invalidates(
            reading: { _ = sut.currencyCode; _ = sut.tracksInventory },
            after: {
                context.insert(IngredientCategory(name: "Oils"))
                try context.save()
            }
        )

        #expect(!invalidated)
        #expect(sut.currencyCode == "USD")
    }

    @Test func save_SettingsChangeThatLeavesReadValuesAlone_DoesNotInvalidate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let record = try makeRecord(currencyCode: "USD", tracksInventory: false, in: context)
        let sut = SettingsState(context: context, locale: locale)

        let invalidated = try invalidates(
            reading: { _ = sut.currencyCode; _ = sut.tracksInventory },
            after: {
                record.pvpFactor += 1
                try context.save()
            }
        )

        #expect(!invalidated)
    }

    @Test func save_CurrencyChange_InvalidatesReaders() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let record = try makeRecord(currencyCode: "USD", in: context)
        let sut = SettingsState(context: context, locale: locale)

        let invalidated = try invalidates(
            reading: { _ = sut.currencyCode },
            after: {
                record.currencyCode = "GBP"
                try context.save()
            }
        )

        #expect(invalidated)
    }

    // MARK: - History check

    @Test func refreshIfSettingsChanged_RecordFromAnotherContext_ShowsItAndReturnsTrue() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try makeRecord(currencyCode: "USD", in: context)
        let sut = SettingsState(context: context, locale: locale)
        try changeRemotely(in: container) { $0.currencyCode = "GBP" }
        #expect(sut.currencyCode == "USD")

        let refreshed = sut.refreshIfSettingsChanged()

        #expect(refreshed)
        #expect(sut.currencyCode == "GBP")
    }

    @Test func refreshIfSettingsChanged_OtherEntityOnly_ReturnsFalse() throws {
        let container = try makeContainer()
        let sut = SettingsState(context: container.mainContext, locale: locale)
        let other = ModelContext(container)
        other.insert(IngredientCategory(name: "Oils"))
        try other.save()

        #expect(!sut.refreshIfSettingsChanged())
    }

    @Test func refreshIfSettingsChanged_NothingChanged_ReturnsFalse() throws {
        let container = try makeContainer()
        let sut = SettingsState(context: container.mainContext, locale: locale)

        #expect(!sut.refreshIfSettingsChanged())
    }

    @Test func refreshIfSettingsChanged_ChangeAlreadyRefreshedBySave_ReturnsFalse() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let record = try makeRecord(currencyCode: "USD", in: context)
        let sut = SettingsState(context: context, locale: locale)
        record.currencyCode = "GBP"
        try context.save()

        #expect(!sut.refreshIfSettingsChanged())
    }

    @Test func refresh_PicksUpChangeFromAnotherContext() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try makeRecord(currencyCode: "USD", in: context)
        let sut = SettingsState(context: context, locale: locale)
        try changeRemotely(in: container) { $0.tracksInventory = true }

        sut.refresh()

        #expect(sut.tracksInventory)
        #expect(!sut.refreshIfSettingsChanged())
    }

    // MARK: - Import events

    @Test func handle_FinishedImport_RefetchesWhenSettingsChanged() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try makeRecord(currencyCode: "USD", in: context)
        let sut = SettingsState(context: context, locale: locale)
        try changeRemotely(in: container) { $0.currencyCode = "GBP" }

        sut.handle(SyncEvent(kind: .import, endDate: .now, succeeded: true, error: nil))

        #expect(sut.currencyCode == "GBP")
    }

    @Test func handle_ImportStillRunning_DoesNothing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try makeRecord(currencyCode: "USD", in: context)
        let sut = SettingsState(context: context, locale: locale)
        try changeRemotely(in: container) { $0.currencyCode = "GBP" }

        sut.handle(SyncEvent(kind: .import, endDate: nil, succeeded: false, error: nil))

        #expect(sut.currencyCode == "USD")
    }

    @Test func handle_FinishedExport_DoesNothing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try makeRecord(currencyCode: "USD", in: context)
        let sut = SettingsState(context: context, locale: locale)
        try changeRemotely(in: container) { $0.currencyCode = "GBP" }

        sut.handle(SyncEvent(kind: .export, endDate: .now, succeeded: true, error: nil))

        #expect(sut.currencyCode == "USD")
    }
}
