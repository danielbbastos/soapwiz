import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Shopping list batch plan")
@MainActor
struct ShoppingListBatchPlanTests: BatchProductionTestHelpers {

    private let container: ModelContainer
    private let context: ModelContext
    private let sut: ShoppingListViewModel

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
        sut = ShoppingListViewModel(modelContext: context)
    }

    private func makeIngredient(_ name: String = "Olive Oil", unit: String = "g") -> Ingredient {
        let ingredient = Ingredient(name: name, unit: unit)
        context.insert(ingredient)
        return ingredient
    }

    private func requirement(_ ingredient: Ingredient, required: Double = 1000, available: Double = 900) -> BatchRequirement {
        BatchRequirement(
            id: ingredient.persistentModelID,
            ingredient: ingredient,
            required: required,
            available: available,
            unit: ingredient.unit
        )
    }

    private func makeItem(
        _ ingredient: Ingredient,
        amount: Double? = 50,
        unit: String? = nil,
        note: String = "",
        createdAt: Date = .now
    ) -> ShoppingListItem {
        let item = ShoppingListItem(
            name: ingredient.name,
            amount: amount,
            unit: unit ?? ingredient.unit,
            ingredient: ingredient,
            note: note
        )
        item.createdAt = createdAt
        context.insert(item)
        return item
    }

    private func plan(
        _ shortages: [BatchRequirement],
        items: [ShoppingListItem] = [],
        boughtDates: [PersistentIdentifier: Date] = [:]
    ) -> [ShoppingListPlannedLine] {
        ShoppingListBatchPlan.lines(
            shortages: shortages,
            recipeName: "Castile",
            batchCount: 2,
            items: items,
            boughtDates: boughtDates
        )
    }

    private func allItems() throws -> [ShoppingListItem] {
        try context.fetch(FetchDescriptor<ShoppingListItem>())
    }

    @Test func lines_NoMatchingItem_PlansNewLine() throws {
        let oil = makeIngredient()

        let line = try #require(plan([requirement(oil)]).first)

        #expect(line.mergeTarget == nil)
        #expect(abs(line.amount - 100) < 1e-6)
        #expect(line.unit == oil.unit)
        #expect(line.note == "For Castile \u{00D7}2")
    }

    @Test func lines_FractionalShortfall_RoundsUpToWholeUnit() throws {
        let oil = makeIngredient()

        let line = try #require(plan([requirement(oil, required: 1000, available: 34.03)]).first)

        #expect(line.amount == 966)
    }

    @Test func lines_ExactShortfallWithFloatNoise_StaysUnchanged() throws {
        let oil = makeIngredient()

        let line = try #require(plan([requirement(oil, required: 480.0000001, available: 0)]).first)

        #expect(line.amount == 480)
    }

    @Test func lines_CoarseUnit_RoundsUpToOneDecimal() throws {
        let flour = makeIngredient("Clay", unit: "kg")

        let line = try #require(plan([requirement(flour, required: 1.23, available: 0)]).first)

        #expect(line.amount == 1.3)
    }

    @Test func lines_CoarseUnitExactTenth_StaysUnchanged() throws {
        let flour = makeIngredient("Clay", unit: "kg")

        let line = try #require(plan([requirement(flour, required: 1.2, available: 0)]).first)

        #expect(line.amount == 1.2)
    }

    @Test func lines_LitreAndPound_RoundToOneDecimal() {
        #expect(ShoppingListBatchPlan.roundedUp(0.41, unit: "L") == 0.5)
        #expect(ShoppingListBatchPlan.roundedUp(2.01, unit: "lb") == 2.1)
        #expect(ShoppingListBatchPlan.roundedUp(2.01, unit: "oz") == 3)
        #expect(ShoppingListBatchPlan.roundedUp(2.01, unit: "ml") == 3)
    }

    @Test func lines_NoiseSizedShortfall_ProducesNoLine() {
        let oil = makeIngredient()

        #expect(plan([requirement(oil, required: 900.0000001, available: 900)]).isEmpty)
    }

    @Test func lines_NotShort_ProducesNoLines() {
        let oil = makeIngredient()

        let lines = plan([requirement(oil, required: 500, available: 900)])

        #expect(lines.isEmpty)
    }

    @Test func lines_UncheckedSameIngredientAndUnit_MergesWithAppendedNote() throws {
        let oil = makeIngredient()
        let item = makeItem(oil, note: "For Rose \u{00D7}1")

        let line = try #require(plan([requirement(oil)], items: [item]).first)

        #expect(line.mergeTarget === item)
        #expect(line.note == "For Rose \u{00D7}1, Castile \u{00D7}2")
    }

    @Test func lines_MergeIntoNoteNotStartingWithFor_UsesSeparator() throws {
        let oil = makeIngredient()
        let item = makeItem(oil, note: "Organic")

        let line = try #require(plan([requirement(oil)], items: [item]).first)

        #expect(line.note == "Organic \u{00B7} For Castile \u{00D7}2")
    }

    @Test func lines_MergeIntoEmptyNote_UsesPlainNote() throws {
        let oil = makeIngredient()
        let item = makeItem(oil, note: "")

        let line = try #require(plan([requirement(oil)], items: [item]).first)

        #expect(line.note == "For Castile \u{00D7}2")
    }

    @Test func lines_SeveralMatches_PicksOldest() throws {
        let oil = makeIngredient()
        let newer = makeItem(oil, createdAt: .now)
        let older = makeItem(oil, createdAt: .now.addingTimeInterval(-86_400))

        let line = try #require(plan([requirement(oil)], items: [newer, older]).first)

        #expect(line.mergeTarget === older)
    }

    @Test func lines_DifferentUnit_PlansNewLine() throws {
        let oil = makeIngredient()
        let item = makeItem(oil, unit: "ml")

        let line = try #require(plan([requirement(oil)], items: [item]).first)

        #expect(line.mergeTarget == nil)
    }

    @Test func lines_CheckedItem_IsNotMergeTarget() throws {
        let oil = makeIngredient()
        let item = makeItem(oil)
        item.isChecked = true

        let line = try #require(plan([requirement(oil)], items: [item]).first)

        #expect(line.mergeTarget == nil)
    }

    @Test func lines_BoughtItem_IsNotMergeTarget() throws {
        let oil = makeIngredient()
        let item = makeItem(oil)

        let line = try #require(
            plan([requirement(oil)], items: [item], boughtDates: [item.persistentModelID: .now]).first
        )

        #expect(line.mergeTarget == nil)
    }

    @Test func lines_ItemOfOtherIngredient_IsNotMergeTarget() throws {
        let oil = makeIngredient()
        let butter = makeIngredient("Shea Butter")
        let item = makeItem(butter)

        let line = try #require(plan([requirement(oil)], items: [item]).first)

        #expect(line.mergeTarget == nil)
    }

    @Test func addPlanned_NewLine_InsertsLinkedItem() throws {
        let oil = makeIngredient()

        sut.addPlanned(plan([requirement(oil)]))

        let item = try #require(try allItems().first)
        #expect(try allItems().count == 1)
        #expect(item.ingredient === oil)
        #expect(abs((item.amount ?? 0) - 100) < 1e-6)
        #expect(item.unit == oil.unit)
        #expect(item.note == "For Castile \u{00D7}2")
    }

    @Test func addPlanned_Merge_RaisesAmountAndUpdatesNote() throws {
        let oil = makeIngredient()
        let item = makeItem(oil, amount: 50, note: "For Rose \u{00D7}1")

        sut.addPlanned(plan([requirement(oil)], items: [item]))

        #expect(try allItems().count == 1)
        #expect(abs((item.amount ?? 0) - 150) < 1e-6)
        #expect(item.note == "For Rose \u{00D7}1, Castile \u{00D7}2")
    }

    @Test func addPlanned_MergeWithFractionalShortfall_AddsRoundedAmount() throws {
        let oil = makeIngredient()
        let item = makeItem(oil, amount: 50)

        sut.addPlanned(plan([requirement(oil, required: 1000, available: 34.03)], items: [item]))

        #expect(item.amount == 1016)
    }

    @Test func addPlanned_MergeIntoNilAmount_TakesShortfall() throws {
        let oil = makeIngredient()
        let item = makeItem(oil, amount: nil)

        sut.addPlanned(plan([requirement(oil)], items: [item]))

        #expect(abs((item.amount ?? 0) - 100) < 1e-6)
    }

    @Test func addPlanned_NoLines_AddsNothing() throws {
        sut.addPlanned([])

        #expect(try allItems().isEmpty)
    }

    @Test func plan_RealRecipeWithShortStock_AddsShortfalls() throws {
        let oil = makeIngredient("Coconut Oil")
        purchase(context, for: oil, quantity: 500, totalPrice: 5, daysAgo: 3)
        purchase(context, for: oil, quantity: 400, totalPrice: 4, daysAgo: 1)
        let recipe = makeRecipe(context, oil: oil, oilWeight: 1000)
        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        model.batchCount = 2

        let shortages = model.shortages(in: model.requirements)
        let shortage = try #require(shortages.first)
        let items = try allItems()
        let purchases = try context.fetch(FetchDescriptor<IngredientPurchase>())
        let lines = ShoppingListBatchPlan.lines(
            shortages: shortages,
            recipeName: recipe.name,
            batchCount: model.batchCount,
            items: items,
            boughtDates: ShoppingListBought.dates(items: items, purchases: purchases)
        )
        sut.addPlanned(lines)

        let added = try #require(try allItems().first)
        #expect(try allItems().count == 1)
        #expect(abs(shortage.shortfall - 1100) < 1e-6)
        #expect(abs((added.amount ?? 0) - shortage.shortfall) < 1e-6)
        #expect(added.unit == shortage.unit)
        #expect(added.ingredient === oil)
        #expect(added.note == "For \(recipe.name) \u{00D7}2")
    }
}
