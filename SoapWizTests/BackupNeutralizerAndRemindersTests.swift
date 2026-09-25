import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The recipe's Failor neutraliser and the expiry reminders setting surviving
/// the backup file (SW-186), and older files without either key.
@Suite("Backup – neutraliser and reminders", .serialized)
@MainActor
struct BackupNeutralizerAndRemindersTests: BackupTestHelpers {

    /// Adds a CFM recipe whose neutraliser is a separate additive, so the
    /// restored link can only point at the right row by index.
    private func seedCFMRecipe(_ ctx: ModelContext) throws {
        seedFullGraph(ctx)
        let additives = IngredientCategory(name: IngredientCategory.Name.additives)
        ctx.insert(additives)
        let boric = Ingredient(name: "Boric Acid", category: additives, unit: "g")
        ctx.insert(boric)
        let recipe = Recipe(name: "Liquid Castile", desc: "")
        recipe.useCFM = true
        recipe.cfmNeutralizer = CFMNeutralizer.boricAcid.rawValue
        recipe.neutralizerIngredient = boric
        ctx.insert(recipe)
        try ctx.save()
    }

    private func recipe(named name: String, in ctx: ModelContext) throws -> Recipe {
        try #require(try ctx.fetch(FetchDescriptor<Recipe>()).first { $0.name == name })
    }

    @Test func roundTrip_PreservesTheNeutraliser() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedCFMRecipe(ctx)

        try roundTripInPlace(ctx)

        #expect(try recipe(named: "Liquid Castile", in: ctx).neutralizerIngredient?.name == "Boric Acid")
        #expect(try recipe(named: "Castile", in: ctx).neutralizerIngredient == nil)
    }

    @Test func restore_BackupWithoutNeutraliserKey_RestoresWithoutOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try seedCFMRecipe(ctx)
        var backup = try BackupService.makeBackup(from: ctx)
        for index in backup.recipes.indices {
            backup.recipes[index].neutralizerIngredientIndex = nil
        }
        let data = try BackupService.encode(backup)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("neutralizerIngredientIndex") == false)

        try BackupService.restore(try BackupService.decode(data), into: ctx)

        let restored = try recipe(named: "Liquid Castile", in: ctx)
        #expect(restored.useCFM)
        #expect(restored.neutralizerIngredient == nil)
    }

    @Test(arguments: [true, false])
    func roundTrip_PreservesTheRemindersSetting(_ enabled: Bool) throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        AppSettings.resolve(in: ctx).expiryNotificationsEnabled = enabled
        try ctx.save()
        let data = try BackupService.encode(try BackupService.makeBackup(from: ctx))
        AppSettings.resolve(in: ctx).expiryNotificationsEnabled = !enabled
        try ctx.save()

        try BackupService.restore(try BackupService.decode(data), into: ctx)

        #expect(AppSettings.resolve(in: ctx).expiryNotificationsEnabled == enabled)
    }

    /// A file that predates the key says nothing about reminders, so a restore
    /// must not switch off the ones this device has on.
    @Test(arguments: [true, false])
    func restore_BackupWithoutRemindersKey_KeepsTheCurrentSetting(_ current: Bool) throws {
        let (container, ctx) = try makeContext()
        _ = container
        seedFullGraph(ctx)
        var backup = try BackupService.makeBackup(from: ctx)
        backup.settings.expiryNotificationsEnabled = nil
        let data = try BackupService.encode(backup)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("expiryNotificationsEnabled") == false)
        AppSettings.resolve(in: ctx).expiryNotificationsEnabled = current
        try ctx.save()

        try BackupService.restore(try BackupService.decode(data), into: ctx)

        #expect(AppSettings.resolve(in: ctx).expiryNotificationsEnabled == current)
    }
}
