import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("BatchHistoryViewModel", .serialized)
@MainActor
struct BatchHistoryViewModelTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self,
            Batch.self, BatchLineItem.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private func date(daysAgo: Int) throws -> Date {
        try #require(Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now))
    }

    // MARK: - Sort order

    @Test func sortedNewestFirst_EmptyList_ReturnsEmpty() {
        #expect(BatchHistoryViewModel.sortedNewestFirst([]).isEmpty)
    }

    @Test func sortedNewestFirst_MultipleBatches_OrdersByDateDescending() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let old = Batch(recipe: nil, recipeName: "Old", dateCreated: try date(daysAgo: 10), batchCount: 1)
        let newest = Batch(recipe: nil, recipeName: "Newest", dateCreated: try date(daysAgo: 0), batchCount: 1)
        let middle = Batch(recipe: nil, recipeName: "Middle", dateCreated: try date(daysAgo: 5), batchCount: 1)
        for batch in [old, newest, middle] { ctx.insert(batch) }

        let sorted = BatchHistoryViewModel.sortedNewestFirst([old, newest, middle])

        #expect(sorted.map(\.recipeName) == ["Newest", "Middle", "Old"])
    }

    // MARK: - Count summary

    private func expectedLine(total: Int, curing: Int) -> String {
        var parts = [String(AttributedString(localized: "^[\(total) batch](inflect: true)").characters)]
        if curing > 0 {
            parts.append(String(localized: "\(curing) curing"))
        }
        return parts.joined(separator: " · ")
    }

    @Test func countSummaryLine_NoBatches_IsNil() {
        #expect(BatchCountSummary(total: 0, curing: 0).line == nil)
    }

    @Test func countSummaryLine_NoneCuring_HasOnlyTheTotal() {
        let line = BatchCountSummary(total: 3, curing: 0).line

        #expect(line == expectedLine(total: 3, curing: 0))
        #expect(line?.contains("·") == false)
    }

    @Test func countSummaryLine_SomeCuring_HasBothFigures() throws {
        let line = try #require(BatchCountSummary(total: 27, curing: 5).line)

        #expect(line == expectedLine(total: 27, curing: 5))
        #expect(line.contains("·"))
    }

    @Test func countSummaryLine_SingleBatch_IsSingular() {
        let line = BatchCountSummary(total: 1, curing: 0).line

        #expect(line == expectedLine(total: 1, curing: 0))
        #expect(line != expectedLine(total: 2, curing: 0))
    }

    @Test func countSummaryCounting_NoBatches_IsZero() {
        #expect(BatchCountSummary(counting: []) == BatchCountSummary(total: 0, curing: 0))
    }

    @Test func countSummaryCounting_MixedBatches_CountsOnlyCuring() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let curing = Batch(recipe: nil, recipeName: "Curing", dateCreated: try date(daysAgo: 2), batchCount: 1, cureDays: 28)
        let ready = Batch(recipe: nil, recipeName: "Ready", dateCreated: try date(daysAgo: 60), batchCount: 1, cureDays: 28)
        let noCure = Batch(recipe: nil, recipeName: "No cure", dateCreated: try date(daysAgo: 1), batchCount: 1)
        for batch in [curing, ready, noCure] { ctx.insert(batch) }

        #expect(BatchCountSummary(counting: [curing, ready, noCure]) == BatchCountSummary(total: 3, curing: 1))
    }

    // MARK: - Search

    private func searchFixture() -> [Batch] {
        [
            Batch(recipe: nil, code: "LAV-260930-01", recipeName: "Lavender", batchCount: 1),
            Batch(recipe: nil, code: "ROS-260930-01", recipeName: "Rose", batchCount: 1),
            Batch(recipe: nil, code: "2026/14", recipeName: "Lavender Oatmeal", batchCount: 1)
        ]
    }

    @Test func filtered_EmptyList_ReturnsEmpty() {
        #expect(BatchHistoryViewModel.filtered([], matching: "LAV").isEmpty)
    }

    @Test(arguments: ["", "   "])
    func filtered_BlankQuery_ReturnsEverything(query: String) {
        #expect(BatchHistoryViewModel.filtered(searchFixture(), matching: query).count == 3)
    }

    @Test func filtered_QueryMatchesCode_ReturnsThatBatch() {
        let result = BatchHistoryViewModel.filtered(searchFixture(), matching: "ROS-2609")

        #expect(result.map(\.code) == ["ROS-260930-01"])
    }

    @Test func filtered_QueryInLowercaseWithSpaces_StillMatchesCode() {
        let result = BatchHistoryViewModel.filtered(searchFixture(), matching: " lav-260930 ")

        #expect(result.map(\.code) == ["LAV-260930-01"])
    }

    @Test func filtered_QueryMatchesRecipeName_ReturnsEveryBatchOfIt() {
        let result = BatchHistoryViewModel.filtered(searchFixture(), matching: "lavender")

        #expect(result.map(\.code) == ["LAV-260930-01", "2026/14"])
    }

    @Test func filtered_HandTypedCode_IsSearchable() {
        let result = BatchHistoryViewModel.filtered(searchFixture(), matching: "2026/")

        #expect(result.map(\.recipeName) == ["Lavender Oatmeal"])
    }

    @Test func filtered_NoMatch_ReturnsEmpty() {
        #expect(BatchHistoryViewModel.filtered(searchFixture(), matching: "Castile").isEmpty)
    }

    // MARK: - Display code

    @Test func displayCode_BatchWithCode_ShowsItTrimmed() {
        let batch = Batch(recipe: nil, code: " LAV-260930-01 ", recipeName: "Lavender", batchCount: 1)

        #expect(BatchHistoryViewModel.displayCode(of: batch) == "LAV-260930-01")
    }

    @Test(arguments: ["", "  "])
    func displayCode_BatchWithoutCode_ShowsADash(code: String) {
        let batch = Batch(recipe: nil, code: code, recipeName: "Lavender", batchCount: 1)

        #expect(BatchHistoryViewModel.displayCode(of: batch) == "—")
    }

    // MARK: - Line item sorting

    @Test func sortedLineItems_NoItems_ReturnsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let batch = Batch(recipe: nil, recipeName: "Soap", batchCount: 1)
        ctx.insert(batch)

        #expect(BatchHistoryViewModel.sortedLineItems(of: batch).isEmpty)
    }

    @Test func sortedLineItems_MultipleItems_OrdersAlphabetically() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let batch = Batch(recipe: nil, recipeName: "Soap", batchCount: 1)
        ctx.insert(batch)
        for name in ["Olive Oil", "Coconut Oil", "Lye"] {
            let item = BatchLineItem(ingredient: nil, ingredientName: name, amountConsumed: 1, unit: "g", cost: 0, draws: [])
            item.batch = batch
            ctx.insert(item)
        }

        let sorted = BatchHistoryViewModel.sortedLineItems(of: batch)

        #expect(sorted.map(\.ingredientName) == ["Coconut Oil", "Lye", "Olive Oil"])
    }

    // MARK: - Cost per batch

    @Test func costPerBatch_MultipleBatches_DividesTotalCost() throws {
        let batch = Batch(recipe: nil, recipeName: "Soap", batchCount: 4, totalCost: 10)

        let cost = try #require(BatchHistoryViewModel.costPerBatch(of: batch))
        #expect(abs(cost - 2.5) < 1e-9)
    }

    @Test func costPerBatch_SingleBatch_EqualsTotalCost() throws {
        let batch = Batch(recipe: nil, recipeName: "Soap", batchCount: 1, totalCost: 7.25)

        let cost = try #require(BatchHistoryViewModel.costPerBatch(of: batch))
        #expect(abs(cost - 7.25) < 1e-9)
    }

    @Test func costPerBatch_ZeroBatchCount_ReturnsZero() {
        let batch = Batch(recipe: nil, recipeName: "Soap", batchCount: 0, totalCost: 10)

        #expect(BatchHistoryViewModel.costPerBatch(of: batch) == 0)
    }

    @Test func costPerBatch_UntrackedBatch_ReturnsNil() {
        let batch = Batch(recipe: nil, recipeName: "Soap", batchCount: 3, tracksInventory: false)

        #expect(BatchHistoryViewModel.costPerBatch(of: batch) == nil)
    }

    /// A tracked batch whose ingredients happened to cost nothing is genuinely
    /// free, and must not be conflated with an untracked one.
    @Test func costPerBatch_TrackedFreeBatch_ReturnsZero() {
        let batch = Batch(recipe: nil, recipeName: "Soap", batchCount: 2, totalCost: 0)

        #expect(BatchHistoryViewModel.costPerBatch(of: batch) == 0)
    }

    // MARK: - Deleted/edited recipe leaves snapshot intact

    @Test func batchSnapshot_RecipeDeleted_KeepsNameAndLineItems() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Lavender Soap")
        ctx.insert(recipe)
        let batch = Batch(recipe: recipe, recipeName: "Lavender Soap", batchCount: 2, totalCost: 12)
        ctx.insert(batch)
        let item = BatchLineItem(
            ingredient: nil, ingredientName: "Olive Oil", amountConsumed: 500, unit: "g", cost: 8,
            draws: [BatchPurchaseDraw(purchaseBadge: "L1", amountDrawn: 500, pricePerUnit: 0.016, cost: 8)]
        )
        item.batch = batch
        ctx.insert(item)
        try ctx.save()

        ctx.delete(recipe)
        try ctx.save()

        let fetched = try #require(try ctx.fetch(FetchDescriptor<Batch>()).first)
        #expect(fetched.recipe == nil)
        #expect(fetched.recipeName == "Lavender Soap")
        #expect(fetched.totalCost == 12)
        let fetchedItem = try #require(fetched.lineItems.first)
        #expect(fetchedItem.ingredientName == "Olive Oil")
        #expect(fetchedItem.amountConsumed == 500)
        let draw = try #require(fetchedItem.draws.first)
        #expect(draw.purchaseBadge == "L1")
        #expect(draw.cost == 8)
    }

    @Test func batchSnapshot_RecipeRenamed_KeepsOriginalName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Lavender Soap")
        ctx.insert(recipe)
        let batch = Batch(recipe: recipe, recipeName: "Lavender Soap", batchCount: 1)
        ctx.insert(batch)
        try ctx.save()

        recipe.name = "Rose Soap"
        try ctx.save()

        #expect(batch.recipeName == "Lavender Soap")
        #expect(batch.recipe?.name == "Rose Soap")
    }
}
