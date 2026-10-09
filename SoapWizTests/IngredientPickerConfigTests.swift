import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Ingredient picker config")
@MainActor
struct IngredientPickerConfigTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    // MARK: - Confirm title

    @Test func confirmTitle_NothingPending_IsPlainAdd() {
        #expect(IngredientPickerView.confirmTitle(count: 0) == String(localized: "Add"))
    }

    @Test func confirmTitle_TwoPending_IncludesCount() {
        #expect(IngredientPickerView.confirmTitle(count: 2) == String(localized: "Add \(2)"))
    }

    // MARK: - Pending selection count

    @Test func pendingCount_TracksInsertsAndToggles() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive", category: nil, unit: "g")
        let castor = Ingredient(name: "Castor", category: nil, unit: "g")
        ctx.insert(olive)
        ctx.insert(castor)
        var pending = PendingIngredientSelection()
        #expect(pending.count == 0)

        pending.insert(olive)
        pending.toggle(castor)
        #expect(pending.count == 2)

        pending.toggle(olive)
        #expect(pending.count == 1)
    }

    // MARK: - Per-role copy

    @Test func pickerConfig_EachSection_HasItsTitleAndNote() {
        typealias Section = RecipeIngredientsTabView.PickerSection
        #expect(Section.oils.pickerConfig.title == "Add Oils")
        #expect(Section.oils.pickerConfig.addedNote == "Oils already in this recipe are dimmed.")
        #expect(Section.additives.pickerConfig.title == "Add Additives")
        #expect(Section.additives.pickerConfig.addedNote == "Additives already in this recipe are dimmed.")
        #expect(Section.fragrances.pickerConfig.title == "Add Fragrances")
        #expect(Section.fragrances.pickerConfig.addedNote == "Fragrances already in this recipe are dimmed.")
        #expect(Section.ingredients.pickerConfig.title == "Add Ingredients")
        #expect(Section.ingredients.pickerConfig.addedNote == "Ingredients already in this recipe are dimmed.")
    }
}
