import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// A reset has to leave the store the way a fresh install would: the library
/// and default settings, and nothing the user added or changed.
@Suite("App reset")
@MainActor
struct AppResetTests: BackupTestHelpers {
    private let library = IngredientLibrary(entries: [
        .mock(slug: "olive-oil", name: "Olive Oil"),
        .mock(slug: "coconut-oil", name: "Coconut Oil")
    ])

    // MARK: - Store

    @Test func eraseStore_FullStore_LeavesNoUserData() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        try ctx.save()

        try AppReset.eraseStore(in: ctx, library: library)

        #expect(try ctx.fetchCount(FetchDescriptor<Batch>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<BatchLineItem>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<Recipe>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<RecipeIngredient>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<RecipeProduct>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<IngredientPurchase>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<Provider>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<StorageLocation>()) == 0)
    }

    @Test func eraseStore_FullStore_InstallsOnlyTheLibrary() throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        try ctx.save()

        try AppReset.eraseStore(in: ctx, library: library)

        let ingredients = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(Set(ingredients.map(\.librarySlug)) == ["olive-oil", "coconut-oil"])
        #expect(ingredients.count == 2)
    }

    /// Hiding is a change the user made, so the reinstalled row starts over.
    @Test func eraseStore_HiddenLibraryIngredient_ComesBackVisible() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)
        for ingredient in try ctx.fetch(FetchDescriptor<Ingredient>()) {
            ingredient.isHidden = true
        }
        try ctx.save()

        try AppReset.eraseStore(in: ctx, library: library)

        let ingredients = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(ingredients.count == 2)
        #expect(ingredients.allSatisfy { !$0.isHidden })
    }

    @Test func eraseStore_ChangedSettings_LeavesOneDefaultRecord() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let settings = AppSettings.resolve(in: ctx)
        let defaults = AppSettings()
        settings.pvpFactor = defaults.pvpFactor + 3
        settings.tracksInventory = !defaults.tracksInventory
        settings.currencyCode = "JPY"
        try ctx.save()

        try AppReset.eraseStore(in: ctx, library: library)

        let records = try ctx.fetch(FetchDescriptor<AppSettings>())
        let reset = try #require(records.first)
        #expect(records.count == 1)
        #expect(reset.pvpFactor == defaults.pvpFactor)
        #expect(reset.tracksInventory == defaults.tracksInventory)
        #expect(reset.currencyCode == defaults.currencyCode)
    }

    @Test func eraseStore_EmptyStore_InstallsTheLibraryAndSettings() throws {
        let (container, ctx) = try makeContext()
        _ = container

        try AppReset.eraseStore(in: ctx, library: library)

        #expect(try ctx.fetchCount(FetchDescriptor<Ingredient>()) == 2)
        #expect(try ctx.fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }

    // MARK: - Device state

    @Test func clearDeviceState_AcknowledgedLyeNotice_AsksAgain() throws {
        let suiteName = "AppResetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        LyeSafetyAcknowledgment(defaults: defaults).acknowledge()

        AppReset.clearDeviceState(defaults: defaults, rollbackDirectory: nil)

        #expect(!LyeSafetyAcknowledgment(defaults: defaults).isAcknowledged)
    }

    /// The sync choice describes the device, not the user's data.
    @Test func clearDeviceState_SyncTurnedOff_StaysOff() throws {
        let suiteName = "AppResetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        SyncPreference(defaults: defaults).usesOffline = true

        AppReset.clearDeviceState(defaults: defaults, rollbackDirectory: nil)

        #expect(SyncPreference(defaults: defaults).usesOffline)
    }

    @Test func clearDeviceState_RollbackFiles_RemovesOnlyThose() throws {
        let suiteName = "AppResetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppResetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rollback = directory.appendingPathComponent(RestoreCoordinator.rollbackFileName(for: .now))
        let other = directory.appendingPathComponent("SoapWiz-Export.json")
        try Data("{}".utf8).write(to: rollback)
        try Data("{}".utf8).write(to: other)

        AppReset.clearDeviceState(defaults: defaults, rollbackDirectory: directory)

        #expect(!FileManager.default.fileExists(atPath: rollback.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    // MARK: - Confirmation

    @Test(arguments: ["DELETE", "delete", " Delete\n"])
    func isConfirmed_TheWordInAnyCaseOrSpacing_IsTrue(_ text: String) {
        #expect(AppReset.isConfirmed(by: text))
    }

    @Test(arguments: ["", "DELET", "DELETE IT", "DE LETE"])
    func isConfirmed_AnythingElse_IsFalse(_ text: String) {
        #expect(!AppReset.isConfirmed(by: text))
    }
}
