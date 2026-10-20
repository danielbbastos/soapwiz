import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// A duplicate merge saves several times; the row stores hold their refetch
/// until it is done (SW-276).
@Suite("Refresh deferral", .serialized)
@MainActor
struct RefreshDeferralTests {

    private struct BodyFailure: Error {}

    private func makeContainer() throws -> ModelContainer {
        let schema = ModelContainerFactory.schema
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
    }

    /// Counts the fetches the inventory makes.
    @MainActor
    private final class CountingFetch {
        private(set) var count = 0

        func fetch(_ context: ModelContext) throws -> InventoryRows.FetchedRows {
            count += 1
            return try InventoryRows.fetchAll(in: context)
        }
    }

    private func saveIngredient(named name: String, in context: ModelContext) throws {
        context.insert(Ingredient(name: name, unit: "g"))
        try context.save()
    }

    // MARK: - InventoryRows

    @Test func inventoryRows_SavesInsideDeferral_DoNotRefetchUntilTheEnd() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = CountingFetch()
        let sut = InventoryRows(context: context, fetchRows: counter.fetch)
        let fetchesBefore = counter.count

        try sut.deferringRefreshes {
            try saveIngredient(named: "Olive Oil", in: context)
            try saveIngredient(named: "Lye", in: context)
            #expect(counter.count == fetchesBefore)
            #expect(sut.ingredients.isEmpty)
        }

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.ingredients.count == 2)
    }

    @Test func inventoryRows_DeferralWithoutRelevantSave_DoesNotRefetch() throws {
        let container = try makeContainer()
        let counter = CountingFetch()
        let sut = InventoryRows(context: container.mainContext, fetchRows: counter.fetch)
        let fetchesBefore = counter.count

        sut.deferringRefreshes {}

        #expect(counter.count == fetchesBefore)
    }

    @Test func inventoryRows_DeferralThatThrows_StillRefetchesOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = CountingFetch()
        let sut = InventoryRows(context: context, fetchRows: counter.fetch)
        let fetchesBefore = counter.count

        #expect(throws: BodyFailure.self) {
            try sut.deferringRefreshes {
                try saveIngredient(named: "Olive Oil", in: context)
                throw BodyFailure()
            }
        }

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.ingredients.map(\.name) == ["Olive Oil"])
    }

    @Test func inventoryRows_NestedDeferral_RefetchesOnlyWhenOutermostEnds() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = CountingFetch()
        let sut = InventoryRows(context: context, fetchRows: counter.fetch)
        let fetchesBefore = counter.count

        try sut.deferringRefreshes {
            try sut.deferringRefreshes {
                try saveIngredient(named: "Olive Oil", in: context)
            }
            #expect(counter.count == fetchesBefore)
            try saveIngredient(named: "Lye", in: context)
        }

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.ingredients.count == 2)
    }

    @Test func inventoryRows_AfterDeferral_SavesRefetchImmediatelyAgain() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = CountingFetch()
        let sut = InventoryRows(context: context, fetchRows: counter.fetch)
        try sut.deferringRefreshes {
            try saveIngredient(named: "Olive Oil", in: context)
        }
        let fetchesBefore = counter.count

        try saveIngredient(named: "Lye", in: context)

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.ingredients.count == 2)
    }

    @Test func inventoryRows_ExplicitRefreshInsideDeferral_SettlesWhatIsOwed() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = CountingFetch()
        let sut = InventoryRows(context: context, fetchRows: counter.fetch)
        let fetchesBefore = counter.count

        try sut.deferringRefreshes {
            try saveIngredient(named: "Olive Oil", in: context)
            sut.refresh()
        }

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.ingredients.count == 1)
    }

    @Test func inventoryRows_SaveAfterExplicitRefreshInsideDeferral_RefetchesOnceMore() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = CountingFetch()
        let sut = InventoryRows(context: context, fetchRows: counter.fetch)
        let fetchesBefore = counter.count

        try sut.deferringRefreshes {
            try saveIngredient(named: "Olive Oil", in: context)
            sut.refresh()
            try saveIngredient(named: "Lye", in: context)
        }

        #expect(counter.count == fetchesBefore + 2)
        #expect(sut.ingredients.count == 2)
    }

    @Test func inventoryRows_DeferralReturnsBodyResult() throws {
        let container = try makeContainer()
        let sut = InventoryRows(context: container.mainContext)

        let result = sut.deferringRefreshes { 42 }

        #expect(result == 42)
    }

    // MARK: - SettingsState

    @Test func settingsState_SavesInsideDeferral_ApplyAtTheEnd() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let sut = SettingsState(context: context, locale: Locale(identifier: "en_GB"))

        try sut.deferringRefreshes {
            let record = AppSettings()
            record.currencyCode = "USD"
            context.insert(record)
            try context.save()
            #expect(sut.currencyCode != "USD")
        }

        #expect(sut.currencyCode == "USD")
    }

    @Test func settingsState_DeferralThatThrows_StillRefetches() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let sut = SettingsState(context: context, locale: Locale(identifier: "en_GB"))

        #expect(throws: BodyFailure.self) {
            try sut.deferringRefreshes {
                let record = AppSettings()
                record.currencyCode = "USD"
                context.insert(record)
                try context.save()
                throw BodyFailure()
            }
        }

        #expect(sut.currencyCode == "USD")
    }

    // MARK: - Merge coordinator

    @Test func coordinator_MergeNow_RunsInsideMergeScope() throws {
        let container = try makeContainer()
        let sut = DuplicateMergeCoordinator(context: container.mainContext)
        var scopeRuns = 0
        sut.mergeScope = { body in
            scopeRuns += 1
            body()
        }

        sut.mergeNow()

        #expect(scopeRuns == 1)
    }
}
