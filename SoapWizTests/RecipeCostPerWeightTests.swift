import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// What each recipe cost per kilogram or pound over the heatmap's window
/// (SW-366).
@Suite("Recipe cost per weight")
@MainActor
struct RecipeCostPerWeightTests {

    private let calendar: Calendar
    private let now: Date
    private let inWindow: Date
    private let window: DateInterval

    init() throws {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Lisbon"))
        calendar.locale = Locale(identifier: "en_US")
        self.calendar = calendar
        now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 15)))
        inWindow = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10)))
        window = BatchHeatmap.window(now: now, calendar: calendar)
    }

    private func entry(
        _ key: String = "A",
        name: String? = nil,
        date: Date? = nil,
        cost: Double = 10,
        weight: Double = 1,
        unit: String = "kg",
        tracks: Bool = true
    ) -> RecipeCostPerWeight.Entry {
        RecipeCostPerWeight.Entry(
            groupKey: key,
            name: name ?? key,
            date: date ?? inWindow,
            cost: cost,
            weight: weight,
            weightUnit: unit,
            tracksInventory: tracks
        )
    }

    private func result(_ entries: [RecipeCostPerWeight.Entry], unit: CostWeightUnit = .kilogram) -> RecipeCostPerWeight {
        RecipeCostPerWeight(entries: entries, window: window, unit: unit)
    }

    private var mixed: [RecipeCostPerWeight.Entry] {
        [
            entry(cost: 10, weight: 500, unit: "g"),
            entry(cost: 20, weight: 1, unit: "kg"),
            entry(cost: 3, weight: 16, unit: "oz"),
            entry(cost: 3, weight: 1, unit: "lb")
        ]
    }

    // MARK: Units

    @Test func costPerUnit_MixedUnitsPerKilogram_DividesTotalCostByTotalKilograms() throws {
        let row = try #require(result(mixed).rows.first)
        #expect(abs(row.costPerUnit - 36 / 2.40718474) < 1e-4)
    }

    @Test func costPerUnit_MixedUnitsPerPound_DividesTotalCostByTotalPounds() throws {
        let row = try #require(result(mixed, unit: .pound).rows.first)
        let pounds = 2.40718474 / 0.45359237
        #expect(abs(row.costPerUnit - 36 / pounds) < 1e-4)
    }

    @Test func preferred_UsLocale_IsPound() {
        #expect(CostWeightUnit.preferred(for: Locale(identifier: "en_US")) == .pound)
        #expect(CostWeightUnit.pound.symbol == "lb")
    }

    @Test func preferred_PortugueseLocale_IsKilogram() {
        #expect(CostWeightUnit.preferred(for: Locale(identifier: "pt_PT")) == .kilogram)
        #expect(CostWeightUnit.kilogram.symbol == "kg")
    }

    // MARK: Recipe link

    @Test func row_WithRecipe_CarriesItToOpen() throws {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        let recipe = Recipe(name: "Castile")
        container.mainContext.insert(recipe)
        var linked = entry("A")
        linked.recipe = recipe
        let row = try #require(result([linked, entry("A")]).rows.first)
        #expect(row.recipe === recipe)
    }

    @Test func row_DeletedRecipeGroupedByName_HasNoRecipe() throws {
        let row = try #require(result([entry("Old soap")]).rows.first)
        #expect(row.recipe == nil)
    }

    // MARK: Exclusions

    @Test func exclusion_BeforeWindowStart_IsLeftOut() throws {
        let before = try #require(calendar.date(byAdding: .second, value: -1, to: window.start))
        #expect(result([entry(date: before)]).isEmpty)
        #expect(!result([entry(date: window.start)]).isEmpty)
    }

    @Test func exclusion_AfterWindowEnd_IsLeftOut() {
        #expect(result([entry(date: window.end)]).isEmpty)
    }

    @Test func exclusion_TrackingOff_IsLeftOut() {
        #expect(result([entry(tracks: false)]).isEmpty)
    }

    @Test func exclusion_ZeroCost_IsLeftOut() {
        #expect(result([entry(cost: 0)]).isEmpty)
    }

    @Test func exclusion_ZeroWeight_IsLeftOut() {
        #expect(result([entry(weight: 0)]).isEmpty)
    }

    @Test func exclusion_NonMassUnit_IsLeftOut() {
        #expect(result([entry(unit: "ml")]).isEmpty)
        #expect(result([entry(unit: "")]).isEmpty)
    }

    @Test func exclusion_OneBatchOut_DoesNotChangeTheRest() throws {
        let row = try #require(result([entry(cost: 10, weight: 1), entry(cost: 99, weight: 0)]).rows.first)
        #expect(row.costPerUnit == 10)
    }

    // MARK: Grouping

    @Test func grouping_DeletedRecipe_GroupsByName() throws {
        let (container, context) = try makeContext()
        _ = container
        context.insert(batch(nil, "Gone", cost: 10))
        context.insert(batch(nil, "Gone", cost: 30))
        let batches = try context.fetch(FetchDescriptor<Batch>())
        let rows = RecipeCostPerWeight(batches: batches, now: now, calendar: calendar, unit: .kilogram).rows
        #expect(rows.count == 1)
        #expect(rows.first?.name == "Gone")
        #expect(rows.first?.costPerUnit == 20)
    }

    @Test func grouping_TwoRecipesSharingAName_StaySeparate() throws {
        let (container, context) = try makeContext()
        _ = container
        let first = Recipe(name: "Bar")
        let second = Recipe(name: "Bar")
        context.insert(first)
        context.insert(second)
        context.insert(batch(first, "Bar", cost: 10))
        context.insert(batch(second, "Bar", cost: 30))
        try context.save()
        let batches = try context.fetch(FetchDescriptor<Batch>())
        let rows = RecipeCostPerWeight(batches: batches, now: now, calendar: calendar, unit: .kilogram).rows
        #expect(rows.map(\.costPerUnit) == [30, 10])
    }

    @Test func grouping_LiveRecipe_UsesItsCurrentName() throws {
        let (container, context) = try makeContext()
        _ = container
        let recipe = Recipe(name: "New name")
        context.insert(recipe)
        context.insert(batch(recipe, "Old name", cost: 10))
        try context.save()
        let batches = try context.fetch(FetchDescriptor<Batch>())
        let rows = RecipeCostPerWeight(batches: batches, now: now, calendar: calendar, unit: .kilogram).rows
        #expect(rows.first?.name == "New name")
    }

    @Test func window_IsTheHeatmapsWindow() throws {
        let (container, context) = try makeContext()
        _ = container
        let edgeBefore = try #require(calendar.date(byAdding: .second, value: -1, to: window.start))
        context.insert(batch(nil, "Edge", cost: 10, date: window.start))
        context.insert(batch(nil, "Early", cost: 10, date: edgeBefore))
        let batches = try context.fetch(FetchDescriptor<Batch>())
        let rows = RecipeCostPerWeight(batches: batches, now: now, calendar: calendar, unit: .kilogram).rows
        #expect(rows.map(\.name) == ["Edge"])
        #expect(window == BatchHeatmap.window(now: now, calendar: calendar))
    }

    // MARK: Rows

    @Test func rows_Sorted_DearestFirst() {
        let rows = result([
            entry("Cheap", cost: 5), entry("Dear", cost: 20), entry("Mid", cost: 10)
        ]).rows
        #expect(rows.map(\.name) == ["Dear", "Mid", "Cheap"])
    }

    @Test func rows_Tie_BrokenByName() {
        let rows = result([entry("B", cost: 10), entry("A", cost: 10)]).rows
        #expect(rows.map(\.name) == ["A", "B"])
    }

    @Test func rows_Fraction_IsShareOfTheDearest() {
        let rows = result([entry("Dear", cost: 20), entry("Half", cost: 10)]).rows
        #expect(rows.map(\.fraction) == [1, 0.5])
    }

    @Test func rows_MoreThanLimit_KeepsTheFiveDearest() {
        let entries = (1...7).map { entry("R\($0)", cost: Double($0)) }
        let rows = result(entries).rows
        #expect(RecipeCostPerWeight.rowLimit == 5)
        #expect(rows.map(\.name) == ["R7", "R6", "R5", "R4", "R3"])
    }

    @Test func isEmpty_NothingQualifies_IsTrue() {
        #expect(result([]).isEmpty)
        #expect(result([entry(cost: 0)]).rows.isEmpty)
    }

    private func batch(_ recipe: Recipe?, _ name: String, cost: Double, date: Date? = nil) -> Batch {
        Batch(
            recipe: recipe,
            recipeName: name,
            dateCreated: date ?? inWindow,
            batchCount: 1,
            totalCost: cost,
            totalWeight: 1,
            totalWeightUnit: "kg"
        )
    }

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }
}
