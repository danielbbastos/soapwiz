import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The onboarding tour's sandbox (SW-291): the sample it holds and the ways it
/// keeps the tour from touching the user's own state.
@Suite("Tour sandbox")
@MainActor
struct TourSandboxTests {

    private let now: Date = {
        let components = DateComponents(year: 2026, month: 6, day: 15, hour: 10)
        return Calendar.current.date(from: components) ?? .distantPast
    }()

    private func makeSandbox(currencyCode: String = "EUR") throws -> TourSandbox {
        try TourSandbox(currencyCode: currencyCode, now: now)
    }

    private func ingredient(_ name: String, in sandbox: TourSandbox) throws -> Ingredient {
        let rows = try sandbox.container.mainContext.fetch(FetchDescriptor<Ingredient>())
        return try #require(rows.first { $0.name == name && !$0.librarySlug.isEmpty })
    }

    /// What is left of an ingredient as a weight in grams, whatever unit the
    /// library stocks it in (olive oil and lavender are by volume).
    private func remainingWeight(_ name: String, in sandbox: TourSandbox) throws -> Double {
        let row = try ingredient(name, in: sandbox)
        let converted = IngredientUnitConverter
            .convert(row.totalRemaining, from: row.unit, to: "g", density: row.density)
        return try #require(converted).value
    }

    private func recipe(in sandbox: TourSandbox) throws -> Recipe {
        let recipes = try sandbox.container.mainContext.fetch(FetchDescriptor<Recipe>())
        return try #require(recipes.first)
    }

    private func cents(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }

    // MARK: - Sample

    @Test func sample_HoldsFivePurchasesFromTheLocalSupplier() throws {
        let sandbox = try makeSandbox()

        let purchases = try sandbox.container.mainContext.fetch(FetchDescriptor<IngredientPurchase>())

        #expect(purchases.count == 5)
        #expect(purchases.allSatisfy { $0.provider?.name == "Local supplier" })
        let names = Set(purchases.compactMap { $0.ingredient?.name })
        #expect(names == [
            "Olive Oil", "Coconut Oil", "Castor Oil", "Lavender Essential Oil", "Sodium Hydroxide (Lye)"
        ])
    }

    @Test func sample_HoldsOneBastilleRecipeWithThreeOilsAndLavender() throws {
        let sandbox = try makeSandbox()

        let recipes = try sandbox.container.mainContext.fetch(FetchDescriptor<Recipe>())
        let recipe = try #require(recipes.first)

        #expect(recipes.count == 1)
        #expect(recipe.name == "Classic Bastille Bar")
        #expect(recipe.recipeKind == RecipeKind.soap.rawValue)
        let oils = recipe.ingredients.filter { $0.ingredientRole == .oil }
        #expect(oils.count == 3)
        #expect(oils.reduce(0) { $0 + $1.percentage } == 100)
        let fragrances = recipe.ingredients.filter { $0.ingredientRole == .fragrance }
        #expect(fragrances.compactMap { $0.ingredient?.name } == ["Lavender Essential Oil"])
    }

    @Test func sample_HoldsOneColdProcessBatchStillCuring() throws {
        let sandbox = try makeSandbox()

        let batches = try sandbox.container.mainContext.fetch(FetchDescriptor<Batch>())
        let batch = try #require(batches.first)

        #expect(batches.count == 1)
        #expect(batch.process == SoapProcess.cold.rawValue)
        #expect(batch.dateCreated == now)
        let status = CureStatus(dateCreated: batch.dateCreated, cureDays: batch.cureDays, now: now)
        guard case .curing = status else {
            Issue.record("Expected the batch to be curing, got \(status)")
            return
        }
    }

    @Test func sample_BatchDrawsStockFromEveryIngredient() throws {
        let sandbox = try makeSandbox()

        // Olive oil and lavender are stocked by volume: 1000 ml less 360 g at
        // 0.911 g/ml, and 100 ml less 15 g at 0.88 g/ml.
        let olive = try ingredient("Olive Oil", in: sandbox).totalRemaining
        let lavender = try ingredient("Lavender Essential Oil", in: sandbox).totalRemaining
        #expect(abs(olive - (1000 - 360 / 0.911)) < 0.001)
        #expect(abs(lavender - (100 - 15 / 0.88)) < 0.001)
        #expect(abs(try remainingWeight("Olive Oil", in: sandbox) - 551) < 0.001)
        #expect(abs(try remainingWeight("Coconut Oil", in: sandbox) - 900) < 0.001)
        #expect(abs(try remainingWeight("Castor Oil", in: sandbox) - 460) < 0.001)
        #expect(abs(try remainingWeight("Lavender Essential Oil", in: sandbox) - 73) < 0.001)
        let lye = try remainingWeight("Sodium Hydroxide (Lye)", in: sandbox)
        #expect(lye < 1000)
        #expect(lye > 900)
    }

    @Test func sample_PurchaseSizesAreRoundInEachIngredientsOwnUnit() throws {
        let sandbox = try makeSandbox()

        let purchases = try sandbox.container.mainContext.fetch(FetchDescriptor<IngredientPurchase>())
        let sizes = Dictionary(uniqueKeysWithValues: purchases.compactMap { purchase in
            purchase.ingredient.map { ($0.name, purchase.quantity) }
        })

        #expect(sizes["Olive Oil"] == 1000)
        #expect(sizes["Coconut Oil"] == 1000)
        #expect(sizes["Castor Oil"] == 500)
        #expect(sizes["Lavender Essential Oil"] == 100)
        #expect(sizes["Sodium Hydroxide (Lye)"] == 1000)
    }

    @Test func sample_StockUnitsMatchTheLibrary() throws {
        let sandbox = try makeSandbox()

        for (name, unit) in TourSample.stockUnits {
            #expect(try ingredient(name, in: sandbox).unit == unit, "\(name)")
        }
    }

    // MARK: - Cost

    @Test func recipeCost_LinesAndTotalMatchTheTourCopy() throws {
        let sandbox = try makeSandbox()
        let engine = RecipeFormViewModel()
        engine.load(from: try recipe(in: sandbox))

        let breakdown = engine.wholeBatchBreakdown

        func lineCost(_ name: String) throws -> Int {
            let rows = breakdown.oils + breakdown.fragrances + breakdown.lye
            return cents(try #require(rows.first { $0.ingredient.name == name }).cost)
        }
        #expect(try lineCost("Olive Oil") == 135)
        #expect(try lineCost("Coconut Oil") == 46)
        #expect(try lineCost("Castor Oil") == 44)
        #expect(try lineCost("Lavender Essential Oil") == 228)
        #expect(cents(breakdown.total) == 506)
        let lyeAmount = try #require(breakdown.lye.first).ingredientAmount
        #expect(abs(lyeAmount - 69.11) < 0.01)
    }

    // MARK: - Dates

    @Test func purchases_AreTwelveDaysOldWithAYearToExpiry() throws {
        let sandbox = try makeSandbox()
        let calendar = Calendar.current
        let bought = try #require(calendar.date(byAdding: .day, value: -12, to: now))
        let expiry = try #require(calendar.date(byAdding: .year, value: 1, to: bought))

        let purchases = try sandbox.container.mainContext.fetch(FetchDescriptor<IngredientPurchase>())

        #expect(purchases.allSatisfy { $0.dateOfPurchase == bought })
        #expect(purchases.allSatisfy { $0.expiryDate == expiry })
        #expect(purchases.allSatisfy { ($0.expiryDate ?? .distantPast) > now })
    }

    // MARK: - Isolation

    @Test func lyeNotice_NeverPresentsInTheSandbox() throws {
        let suiteName = "pt.tachyon.SoapWiz.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sut = LyeSafetyAcknowledgment(defaults: defaults)

        #expect(sut.shouldPresent(makesSoap: true, isTourSandbox: true) == false)
        #expect(sut.shouldPresent(makesSoap: true, isTourSandbox: false) == true)
        #expect(sut.shouldPresent(makesSoap: true) == true)
        #expect(sut.isAcknowledged == false)
    }

    @Test func isSandbox_TrueOnlyForTheLiveSandboxContext() throws {
        let other = try ModelContainer(
            for: ModelContainerFactory.schema,
            configurations: ModelConfiguration.inMemory(ModelContainerFactory.schema)
        )
        let sandbox = try makeSandbox()

        #expect(TourSandbox.isSandbox(sandbox.container.mainContext))
        #expect(TourSandbox.isSandbox(other.mainContext) == false)
    }

    @Test func isSandbox_FalseOnceTheSandboxIsReleased() throws {
        let probe = try ModelContainer(
            for: ModelContainerFactory.schema,
            configurations: ModelConfiguration.inMemory(ModelContainerFactory.schema)
        )
        weak var released: ModelContainer?
        do {
            let sandbox = try makeSandbox()
            released = sandbox.container
            #expect(TourSandbox.isSandbox(sandbox.container.mainContext))
        }

        #expect(released == nil)
        #expect(TourSandbox.isSandbox(probe.mainContext) == false)
    }

    @Test func isSandbox_TwoAliveAtOnce_TrueForBothUntilOneIsReleased() throws {
        let other = try ModelContainer(
            for: ModelContainerFactory.schema,
            configurations: ModelConfiguration.inMemory(ModelContainerFactory.schema)
        )
        let first = try makeSandbox()
        var second: TourSandbox? = try makeSandbox()
        let secondContext = try #require(second?.container.mainContext)

        #expect(TourSandbox.isSandbox(first.container.mainContext))
        #expect(TourSandbox.isSandbox(secondContext))

        second = nil

        #expect(second == nil)
        #expect(TourSandbox.isSandbox(first.container.mainContext))
        #expect(TourSandbox.isSandbox(other.mainContext) == false)
    }

    // MARK: - Reminders

    @Test func syncs_SandboxContext_IsFalse() throws {
        let sandbox = try makeSandbox()

        #expect(NotificationService.syncs(in: sandbox.container.mainContext) == false)
    }

    @Test func syncs_OrdinaryContext_IsTrue() throws {
        let other = try ModelContainer(
            for: ModelContainerFactory.schema,
            configurations: ModelConfiguration.inMemory(ModelContainerFactory.schema)
        )

        #expect(NotificationService.syncs(in: other.mainContext))
    }

    @Test func build_DoesNotTouchTheActiveStore() throws {
        let before = ModelContainerFactory.activeStore

        _ = try makeSandbox()

        #expect(ModelContainerFactory.activeStore == before)
    }

    @Test func build_LeavesTheSyncStatusInTheThrowawaySuite() throws {
        let before = SyncStatusStore().lastSuccessfulSync

        let sandbox = try makeSandbox()

        #expect(sandbox.syncHealth.health == .turnedOff)
        #expect(SyncStatusStore().lastSuccessfulSync == before)
    }

    // MARK: - Settings

    @Test func settings_CarryTheCurrencyAndTrackStock() throws {
        let sandbox = try makeSandbox(currencyCode: "USD")
        let settings = AppSettings.resolve(in: sandbox.container.mainContext)

        #expect(settings.currencyCode == "USD")
        #expect(settings.tracksInventory)
        #expect(sandbox.settings.currencyCode == "USD")
        #expect(sandbox.settings.tracksInventory)
    }

    @Test func inventoryRows_ListTheSampleStock() throws {
        let sandbox = try makeSandbox()

        #expect(sandbox.inventoryRows.purchases.count == 5)
    }

    // MARK: - Speed

    /// The spike measured about 170 ms on an iPhone simulator and 215 ms on an
    /// iPad Pro. The budget is generous so a slow CI machine doesn't fail it.
    @Test func build_FinishesWithinTheBudget() throws {
        let sandbox = try makeSandbox()

        #expect(sandbox.buildDuration < .seconds(2))
    }
}
