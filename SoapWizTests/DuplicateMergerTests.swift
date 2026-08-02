import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// CloudKit cannot enforce uniqueness, so duplicates arrive by sync and every
/// device has to collapse them to the same survivor without coordinating.
@Suite("Duplicate merger", .serialized)
@MainActor
struct DuplicateMergerTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    private func category(_ name: String, _ uuid: UUID) -> IngredientCategory {
        let category = IngredientCategory(name: name)
        category.uuid = uuid
        return category
    }

    // MARK: - Cross-device convergence

    /// The test this whole design exists for. Two devices hold the same synced
    /// rows in different local order and with different amounts of the import
    /// applied. If they disagree about the winner, both delete the other's and
    /// the category is lost entirely.
    @Test func mergeAll_TwoDevicesDisagreeingOnOrder_KeepTheSameWinner() throws {
        let uuidA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        let uuidB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        let first = try #require(uuidA)
        let second = try #require(uuidB)

        func survivorUUID(insertingInReverse reversed: Bool, withIngredient: Bool) throws -> UUID {
            let (container, ctx) = try makeContext()
            _ = container
            let one = category("Oils", first)
            let two = category("Oils", second)
            for model in reversed ? [two, one] : [one, two] {
                ctx.insert(model)
            }
            if withIngredient {
                let ingredient = Ingredient(name: "Olive Oil", category: two, unit: "g")
                ctx.insert(ingredient)
            }
            try ctx.save()

            try DuplicateMerger.mergeAll(in: ctx)

            let remaining = try ctx.fetch(FetchDescriptor<IngredientCategory>())
            #expect(remaining.count == 1)
            return try #require(remaining.first?.uuid)
        }

        let deviceA = try survivorUUID(insertingInReverse: false, withIngredient: false)
        let deviceB = try survivorUUID(insertingInReverse: true, withIngredient: true)

        #expect(deviceA == deviceB)
        #expect(deviceA == first)
    }

    @Test func mergeAll_WinnerIsLowestUUID_RegardlessOfInsertionOrder() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let high = try #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))
        let low = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        ctx.insert(category("Oils", high))
        ctx.insert(category("Oils", low))
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<IngredientCategory>())
        #expect(remaining.map(\.uuid) == [low])
    }

    // MARK: - Repointing

    @Test func mergeAll_DuplicateCategories_RepointEveryIngredient() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = category("Oils", try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")))
        let drop = category("oils", try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")))
        ctx.insert(keep)
        ctx.insert(drop)
        ctx.insert(Ingredient(name: "Olive Oil", category: keep, unit: "g"))
        ctx.insert(Ingredient(name: "Coconut Oil", category: drop, unit: "g"))
        ctx.insert(Ingredient(name: "Castor Oil", category: drop, unit: "g"))
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let categories = try ctx.fetch(FetchDescriptor<IngredientCategory>())
        let ingredients = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(categories.count == 1)
        #expect(ingredients.count == 3)
        #expect(ingredients.allSatisfy { $0.category?.uuid == keep.uuid })
        #expect(keep.ingredients.count == 3)
    }

    @Test func mergeAll_DuplicateProviders_RepointPurchasesAndFoldFields() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = Provider(name: "Acme")
        keep.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let drop = Provider(name: "  acme  ", website: "acme.example", notes: "fast delivery")
        drop.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        ctx.insert(keep)
        ctx.insert(drop)
        let purchase = IngredientPurchase.mock(quantity: 500)
        purchase.provider = drop
        ctx.insert(purchase)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let providers = try ctx.fetch(FetchDescriptor<Provider>())
        #expect(providers.count == 1)
        #expect(try ctx.fetch(FetchDescriptor<IngredientPurchase>()).count == 1)
        #expect(purchase.provider?.uuid == keep.uuid)
        #expect(keep.website == "acme.example")
        #expect(keep.notes == "fast delivery")
    }

    @Test func mergeAll_WinnerAlreadyHasField_KeepsItsOwn() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = Provider(name: "Acme", website: "keep.example")
        keep.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let drop = Provider(name: "Acme", website: "drop.example")
        drop.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        ctx.insert(keep)
        ctx.insert(drop)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(keep.website == "keep.example")
    }

    @Test func mergeAll_DuplicateStorageLocations_RepointPurchases() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = StorageLocation(name: "Shelf A")
        keep.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let drop = StorageLocation(name: "shelf a", locationDescription: "by the window")
        drop.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        ctx.insert(keep)
        ctx.insert(drop)
        let purchase = IngredientPurchase.mock(quantity: 500)
        purchase.storageLocation = drop
        ctx.insert(purchase)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(try ctx.fetch(FetchDescriptor<StorageLocation>()).count == 1)
        #expect(purchase.storageLocation?.uuid == keep.uuid)
        #expect(keep.locationDescription == "by the window")
    }

    // MARK: - Name normalisation

    @Test func mergeAll_NamesDifferingByCaseAccentsOrSpacing_AllCollapse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        for (index, name) in ["Olive Oil", "olive oil", "  Olive  Oil  ", "Ólive Oil"].enumerated() {
            let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index + 1)"))
            ctx.insert(category(name, uuid))
        }
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<IngredientCategory>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.name == "Olive Oil")
    }

    @Test func mergeAll_DistinctNames_AreLeftAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        for (index, name) in ["Oils", "Waxes", "Fats"].enumerated() {
            let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index + 1)"))
            ctx.insert(category(name, uuid))
        }
        ctx.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<IngredientCategory>())
        #expect(remaining.count == 3)
        #expect(Set(remaining.map(\.name)) == ["Oils", "Waxes", "Fats"])
    }

    // MARK: - AppSettings

    @Test func mergeAll_MultipleSettings_CollapseAndKeepChosenValues() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let untouched = AppSettings()
        untouched.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let edited = AppSettings()
        edited.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        edited.pvpFactor = 5.5
        edited.expiryNotificationsEnabled = true
        let third = AppSettings()
        third.uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        for settings in [untouched, edited, third] {
            ctx.insert(settings)
        }
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<AppSettings>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.uuid == untouched.uuid)
        #expect(remaining.first?.pvpFactor == 5.5)
        #expect(remaining.first?.expiryNotificationsEnabled == true)
    }

    @Test func canonical_EmptyRecords_ReturnsNil() {
        #expect(AppSettings.canonical(from: []) == nil)
    }

    @Test func resolve_EmptyStore_InsertsExactlyOneAndIsStable() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let first = AppSettings.resolve(in: ctx)
        try ctx.save()
        let second = AppSettings.resolve(in: ctx)

        #expect(first === second)
        #expect(try ctx.fetch(FetchDescriptor<AppSettings>()).count == 1)
    }

    // MARK: - Rows migrated with a shared uuid

    /// Automatic lightweight migration can fill a newly added attribute from a
    /// default it evaluates once, giving every pre-existing row the same uuid. The
    /// merge has to make them distinct before it tie-breaks on them, or the sort
    /// falls back to fetch order and two devices can pick different winners.
    @Test func mergeAll_DistinctNamesSharingOneUUID_MintsDistinctUUIDs() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let migrated = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        for name in ["Oils", "Waxes", "Fats"] {
            ctx.insert(category(name, migrated))
        }
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<IngredientCategory>())
        #expect(remaining.count == 3)
        #expect(Set(remaining.map(\.uuid)).count == 3)
        #expect(ctx.hasChanges == false)
    }

    @Test func mergeAll_DuplicateNamesSharingOneUUID_StillCollapseToOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let migrated = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let one = category("Oils", migrated)
        let two = category("Oils", migrated)
        ctx.insert(one)
        ctx.insert(two)
        ctx.insert(Ingredient(name: "Olive Oil", category: two, unit: "g"))
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<IngredientCategory>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.ingredients.count == 1)
    }

    @Test func mergeAll_SettingsSharingOneUUID_CollapseAndFoldValues() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let migrated = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let untouched = AppSettings()
        untouched.uuid = migrated
        let edited = AppSettings()
        edited.uuid = migrated
        edited.pvpFactor = 5.5
        ctx.insert(untouched)
        ctx.insert(edited)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<AppSettings>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.pvpFactor == 5.5)
    }

    /// Minting must settle: a second pass has nothing left to make distinct, so it
    /// must not hand the same rows new uuids again and resync them forever.
    @Test func mergeAll_MintedUUIDs_AreStableOnASecondPass() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let migrated = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        for name in ["Oils", "Waxes"] {
            ctx.insert(category(name, migrated))
        }
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)
        let afterFirst = try ctx.fetch(FetchDescriptor<IngredientCategory>())
            .map(\.uuid).sorted { $0.uuidString < $1.uuidString }

        try DuplicateMerger.mergeAll(in: ctx)
        let afterSecond = try ctx.fetch(FetchDescriptor<IngredientCategory>())
            .map(\.uuid).sorted { $0.uuidString < $1.uuidString }

        #expect(afterFirst == afterSecond)
        #expect(ctx.hasChanges == false)
    }

    // MARK: - Idempotency

    @Test func mergeAll_RunTwice_SecondPassChangesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = category("Oils", try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")))
        let drop = category("OILS", try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")))
        ctx.insert(keep)
        ctx.insert(drop)
        ctx.insert(Ingredient(name: "Olive Oil", category: drop, unit: "g"))
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)
        let afterFirst = try ctx.fetch(FetchDescriptor<IngredientCategory>()).map(\.uuid)

        try DuplicateMerger.mergeAll(in: ctx)
        let afterSecond = try ctx.fetch(FetchDescriptor<IngredientCategory>()).map(\.uuid)

        #expect(afterFirst == afterSecond)
        #expect(ctx.hasChanges == false)
        #expect(keep.ingredients.count == 1)
    }

    @Test func mergeAll_NoDuplicates_LeavesStoreUntouched() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(category("Oils", try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))))
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(ctx.hasChanges == false)
        #expect(try ctx.fetch(FetchDescriptor<IngredientCategory>()).count == 1)
    }

    @Test func mergeAll_EmptyStore_DoesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(try ctx.fetch(FetchDescriptor<IngredientCategory>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<AppSettings>()).isEmpty)
    }
}
