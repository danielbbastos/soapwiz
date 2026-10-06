import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Inventory counts")
@MainActor
struct IngredientListCountsTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let model = IngredientListViewModel()

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
    }

    private func makeIngredient(
        _ name: String,
        category: IngredientCategory? = nil,
        remaining: Double? = 500,
        threshold: Double? = nil,
        hidden: Bool = false
    ) -> Ingredient {
        let ingredient = Ingredient(name: name, category: category, unit: "g")
        ingredient.lowStockThreshold = threshold
        ingredient.isHidden = hidden
        context.insert(ingredient)
        if let remaining {
            let purchase = IngredientPurchase(
                dateOfPurchase: .now,
                quantity: 1000,
                totalPrice: 10,
                badge: "",
                journalCode: "",
                expiryDate: nil,
                openingDate: nil
            )
            purchase.remainingAmount = remaining
            ingredient.purchases.append(purchase)
        }
        return ingredient
    }

    private func countSummary(_ ingredients: [Ingredient]) -> InventoryCountSummary {
        model.content(for: ingredients).summary
    }

    private func categoryCounts(_ ingredients: [Ingredient]) -> (all: Int, byCategory: [PersistentIdentifier: Int]) {
        model.content(for: ingredients).categoryCounts
    }

    private func makeCategory(_ name: String) -> IngredientCategory {
        let category = IngredientCategory(name: name)
        context.insert(category)
        return category
    }

    // MARK: - Count line

    @Test func countSummary_NoIngredients_HasNoLine() {
        let summary = countSummary([])

        #expect(summary == InventoryCountSummary(total: 0, low: 0, out: 0))
        #expect(summary.line == nil)
    }

    @Test func countSummary_AllInStock_HasNeitherPart() {
        let summary = countSummary([makeIngredient("A"), makeIngredient("B")])

        #expect(summary == InventoryCountSummary(total: 2, low: 0, out: 0))
        #expect(summary.line?.contains("low") == false)
        #expect(summary.line?.contains("out") == false)
    }

    @Test func countSummary_LowOnly_CountsLowNotOut() {
        let ingredients = [makeIngredient("Fine"), makeIngredient("Low", remaining: 50, threshold: 100)]

        #expect(countSummary(ingredients) == InventoryCountSummary(total: 2, low: 1, out: 0))
    }

    @Test func countSummary_OutOnly_CountsOutNotLow() {
        let ingredients = [makeIngredient("Fine"), makeIngredient("Out", remaining: 0, threshold: 100)]

        #expect(countSummary(ingredients) == InventoryCountSummary(total: 2, low: 0, out: 1))
    }

    @Test func countSummary_LowAndOut_CountedSeparately() {
        let ingredients = [
            makeIngredient("Fine"),
            makeIngredient("Low", remaining: 50, threshold: 100),
            makeIngredient("Out", remaining: 0)
        ]

        #expect(countSummary(ingredients) == InventoryCountSummary(total: 3, low: 1, out: 1))
    }

    private func expectedLine(total: Int, low: Int, out: Int) -> String {
        var parts = [String(AttributedString(localized: "^[\(total) ingredient](inflect: true)").characters)]
        if low > 0 { parts.append(String(localized: "\(low) low")) }
        if out > 0 { parts.append(String(localized: "\(out) out")) }
        return parts.joined(separator: " · ")
    }

    private func parts(of line: String?) -> [String] {
        (line ?? "").components(separatedBy: " · ")
    }

    @Test func line_NothingToCount_IsNil() {
        #expect(InventoryCountSummary(total: 0, low: 0, out: 0).line == nil)
    }

    @Test func line_OnlyTotal_HasOnePart() {
        let line = InventoryCountSummary(total: 1, low: 0, out: 0).line

        #expect(line != nil)
        #expect(parts(of: line).count == 1)
    }

    @Test func line_LowOnly_HasTwoParts() {
        let line = InventoryCountSummary(total: 5, low: 2, out: 0).line

        #expect(parts(of: line).count == 2)
        #expect(line == expectedLine(total: 5, low: 2, out: 0))
    }

    @Test func line_OutOnly_HasTwoParts() {
        let line = InventoryCountSummary(total: 5, low: 0, out: 1).line

        #expect(parts(of: line).count == 2)
        #expect(line == expectedLine(total: 5, low: 0, out: 1))
    }

    @Test func line_LowAndOut_HasThreePartsWithTheirFigures() throws {
        let line = try #require(InventoryCountSummary(total: 5, low: 2, out: 1).line)
        let split = parts(of: line)

        #expect(split.count == 3)
        #expect(split[0].contains(5.formatted()))
        #expect(split[1].contains(2.formatted()))
        #expect(split[2].contains(1.formatted()))
        #expect(line == expectedLine(total: 5, low: 2, out: 1))
    }

    @Test func line_SingleAndMultiple_InflectDifferently() {
        let one = InventoryCountSummary(total: 1, low: 0, out: 0).line
        let many = InventoryCountSummary(total: 5, low: 0, out: 0).line

        #expect(one == expectedLine(total: 1, low: 0, out: 0))
        #expect(many == expectedLine(total: 5, low: 0, out: 0))
    }

    @Test func countSummary_HiddenIngredients_Excluded() {
        let ingredients = [
            makeIngredient("Shown"),
            makeIngredient("Hidden low", remaining: 0, hidden: true)
        ]

        #expect(countSummary(ingredients) == InventoryCountSummary(total: 1, low: 0, out: 0))
    }

    @Test func countSummary_NeverBought_NotCountedAsLowOrOut() {
        let ingredients = [makeIngredient("Unbought", remaining: nil, threshold: 100)]

        #expect(countSummary(ingredients) == InventoryCountSummary(total: 1, low: 0, out: 0))
    }

    @Test func countSummary_InventoryNotTracked_NothingLowOrOut() {
        model.tracksInventory = false
        let ingredients = [makeIngredient("Out", remaining: 0), makeIngredient("Low", remaining: 50, threshold: 100)]

        #expect(countSummary(ingredients) == InventoryCountSummary(total: 2, low: 0, out: 0))
    }

    // MARK: - Category counts

    @Test func categoryCounts_CountsPerCategoryAndAll() {
        let oils = makeCategory("Oils")
        let lyes = makeCategory("Lyes")
        let ingredients = [
            makeIngredient("Olive", category: oils),
            makeIngredient("Coconut", category: oils),
            makeIngredient("Lye", category: lyes),
            makeIngredient("Loose")
        ]

        let counts = categoryCounts(ingredients)

        #expect(counts.all == 4)
        #expect(counts.byCategory[oils.persistentModelID] == 2)
        #expect(counts.byCategory[lyes.persistentModelID] == 1)
    }

    @Test func categoryCounts_IgnoreTheCategorySelection() {
        let oils = makeCategory("Oils")
        let lyes = makeCategory("Lyes")
        let ingredients = [
            makeIngredient("Olive", category: oils),
            makeIngredient("Lye", category: lyes)
        ]
        model.toggleCategory(oils)

        let counts = categoryCounts(ingredients)

        #expect(counts.all == 2)
        #expect(counts.byCategory[lyes.persistentModelID] == 1)
    }

    @Test func categoryCounts_RespectSearch() {
        let oils = makeCategory("Oils")
        let ingredients = [
            makeIngredient("Olive Oil", category: oils),
            makeIngredient("Coconut Oil", category: oils)
        ]
        model.searchText = "olive"

        let counts = categoryCounts(ingredients)

        #expect(counts.all == 1)
        #expect(counts.byCategory[oils.persistentModelID] == 1)
    }

    @Test func categoryCounts_RespectStockFilter() {
        let oils = makeCategory("Oils")
        let ingredients = [
            makeIngredient("Olive", category: oils),
            makeIngredient("Coconut", category: oils, remaining: 0)
        ]
        model.stockStatus = .outOfStock

        let counts = categoryCounts(ingredients)

        #expect(counts.all == 1)
        #expect(counts.byCategory[oils.persistentModelID] == 1)
    }

    @Test func categoryCounts_HiddenExcluded() {
        let oils = makeCategory("Oils")
        let ingredients = [
            makeIngredient("Olive", category: oils),
            makeIngredient("Coconut", category: oils, hidden: true)
        ]

        let counts = categoryCounts(ingredients)

        #expect(counts.all == 1)
        #expect(counts.byCategory[oils.persistentModelID] == 1)
    }

    @Test func categoryCounts_EmptyCategory_HasNoEntry() {
        let oils = makeCategory("Oils")

        let counts = categoryCounts([makeIngredient("Loose")])

        #expect(counts.byCategory[oils.persistentModelID] == nil)
    }

    // MARK: - Combined content

    @Test func content_Displayed_MatchesFilteredFavouritesFirst() {
        let oils = makeCategory("Oils")
        let plain = makeIngredient("Almond", category: oils)
        let favourite = makeIngredient("Walnut", category: oils)
        favourite.isFavorite = true
        let other = makeIngredient("Lye", category: makeCategory("Lyes"))
        model.toggleCategory(oils)

        let content = model.content(for: [plain, favourite, other])

        #expect(content.displayed.map(\.name) == [favourite.name, plain.name])
        #expect(content.displayed.map(\.name) == model.filtered([plain, favourite, other]).favoritesFirst.map(\.name))
    }

    @Test func content_CategorySelection_NarrowsListButNotCountsOrSummary() {
        let oils = makeCategory("Oils")
        let lyes = makeCategory("Lyes")
        let ingredients = [makeIngredient("Olive", category: oils), makeIngredient("Lye", category: lyes)]
        model.toggleCategory(oils)

        let content = model.content(for: ingredients)

        #expect(content.displayed.count == 1)
        #expect(content.categoryCounts.all == 2)
        #expect(content.summary.total == 2)
    }

    @Test func content_Summary_IgnoresSearch() {
        let ingredients = [makeIngredient("Olive"), makeIngredient("Lye")]
        model.searchText = "olive"

        let content = model.content(for: ingredients)

        #expect(content.displayed.count == 1)
        #expect(content.summary.total == 2)
    }

    @Test func content_LowAndOut_AgreeWithRowStamps() {
        let ingredients = [
            makeIngredient("Fine", remaining: 500, threshold: 100),
            makeIngredient("Low", remaining: 50, threshold: 100),
            makeIngredient("AtThreshold", remaining: 100, threshold: 100),
            makeIngredient("Out", remaining: 0, threshold: 100),
            makeIngredient("OutNoThreshold", remaining: 0),
            makeIngredient("Never", remaining: nil, threshold: 100)
        ]
        let expired = makeIngredient("ExpiredLow", remaining: 10, threshold: 100)
        expired.purchases.first?.expiryDate = Calendar.current.date(byAdding: .day, value: -3, to: .now)
        let all = ingredients + [expired]

        let stamps = all.map { IngredientStockStamp.stamps(for: $0, tracksInventory: true) }
        let summary = countSummary(all)

        #expect(summary.low == stamps.filter { $0.contains(.low) }.count)
        #expect(summary.out == stamps.filter { $0.contains(.out) }.count)
        #expect(summary.low == 3)
        #expect(summary.out == 2)
    }

    @Test func filtered_StillAppliesCategorySelection() {
        let oils = makeCategory("Oils")
        let lyes = makeCategory("Lyes")
        let olive = makeIngredient("Olive", category: oils)
        let ingredients = [olive, makeIngredient("Lye", category: lyes)]
        model.toggleCategory(oils)

        #expect(model.filtered(ingredients).map(\.name) == [olive.name])
    }
}
