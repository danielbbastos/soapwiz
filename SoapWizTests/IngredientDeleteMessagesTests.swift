import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Wording of the two alerts on the ingredient delete flow. Both messages are built
/// in the ViewModel rather than the view so they can be asserted directly.
@Suite("Ingredient delete messages", .serialized)
@MainActor
struct IngredientDeleteMessagesTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self,
            StorageLocation.self, Provider.self,
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Batch.self, BatchLineItem.self, AppSettings.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    // MARK: - Blocking message

    @Test func deleteBlockedMessage_NothingBlocked_IsEmpty() {
        let model = IngredientListViewModel()
        #expect(model.deleteBlockedMessage.isEmpty)
    }

    @Test func deleteBlockedMessage_SingleIngredient_NamesEveryBlockingRecipe() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(olive)
        for name in ["Bastille", "Castile"] {
            let recipe = Recipe(name: name)
            ctx.insert(recipe)
            let line = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
            line.recipe = recipe
            ctx.insert(line)
        }
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)
        let message = model.deleteBlockedMessage

        #expect(message.contains("Olive Oil"))
        #expect(message.contains("Bastille"))
        #expect(message.contains("Castile"))
        #expect(message.contains("those recipes"))
    }

    @Test func deleteBlockedMessage_SingleRecipe_UsesSingularWording() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(olive)
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)
        let message = model.deleteBlockedMessage

        #expect(message.contains("is used in Bastille."))
        #expect(message.contains("that recipe"))
    }

    /// Alert messages don't scroll, so the list is capped. Spelling out 25 names
    /// produced a 515-character message that the system simply truncated.
    @Test func deleteBlockedMessage_ManyRecipes_ListsFirstThreeAndSummarisesTheRest() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(olive)
        for index in 1...25 {
            let recipe = Recipe(name: "Recipe \(String(format: "%02d", index))")
            ctx.insert(recipe)
            let line = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
            line.recipe = recipe
            ctx.insert(line)
        }
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)
        let message = model.deleteBlockedMessage

        #expect(message.contains("and 22 others"))
        #expect(message.contains("Recipe 01"))
        #expect(message.contains("Recipe 03"))
        #expect(message.contains("Recipe 04") == false)
        #expect(message.count < 160)
    }

    @Test func deleteBlockedMessage_FourRecipes_UsesSingularOther() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(olive)
        for index in 1...4 {
            let recipe = Recipe(name: "Recipe \(index)")
            ctx.insert(recipe)
            let line = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
            line.recipe = recipe
            ctx.insert(line)
        }
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)

        #expect(model.deleteBlockedMessage.contains("and 1 other"))
        #expect(model.deleteBlockedMessage.contains("and 1 others") == false)
    }

    @Test func deleteBlockedMessage_ThreeRecipes_ListsAllWithoutTruncating() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(olive)
        for name in ["Bastille", "Castile", "Coconut Bar"] {
            let recipe = Recipe(name: name)
            ctx.insert(recipe)
            let line = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
            line.recipe = recipe
            ctx.insert(line)
        }
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)

        #expect(model.deleteBlockedMessage.contains("Coconut Bar"))
        #expect(model.deleteBlockedMessage.contains("other") == false)
    }

    // MARK: - Confirmation message

    @Test func deleteConfirmationMessage_NothingPending_IsEmpty() {
        let model = IngredientListViewModel()
        #expect(model.deleteConfirmationMessage.isEmpty)
    }

    @Test func deleteConfirmationMessage_SingleWithNoPurchases_NamesItAndWarnsNoUndo() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(olive)
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)
        let message = model.deleteConfirmationMessage

        #expect(message.contains("Olive Oil"))
        #expect(message.contains("can't be undone"))
        #expect(message.contains("purchase") == false)
    }

    @Test func deleteConfirmationMessage_WithPurchases_MentionsPurchaseCount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(olive)
        for badge in ["L1", "L2"] {
            let purchase = IngredientPurchase(
                dateOfPurchase: .now, quantity: 1000, totalPrice: 8,
                badge: badge, journalCode: "J", expiryDate: nil, openingDate: nil
            )
            purchase.ingredient = olive
            ctx.insert(purchase)
        }
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)
        let message = model.deleteConfirmationMessage

        #expect(message.contains("2 purchases"))
        #expect(message.contains("can't be undone"))
    }

    @Test func deleteConfirmationMessage_SinglePurchase_UsesSingularWording() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(olive)
        let purchase = IngredientPurchase(
            dateOfPurchase: .now, quantity: 1000, totalPrice: 8,
            badge: "L1", journalCode: "J", expiryDate: nil, openingDate: nil
        )
        purchase.ingredient = olive
        ctx.insert(purchase)
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)

        #expect(model.deleteConfirmationMessage.contains("1 purchase."))
    }

    @Test func deleteBlockedMessage_MultipleIngredients_ListsEachName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let coconut = Ingredient(name: "Coconut Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        [olive, coconut].forEach { ctx.insert($0) }
        ctx.insert(recipe)
        for ingredient in [olive, coconut] {
            let line = RecipeIngredient(ingredient: ingredient, percentage: 50, role: .oil)
            line.recipe = recipe
            ctx.insert(line)
        }
        try ctx.save()

        let model = IngredientListViewModel()
        model.selection = [olive.persistentModelID, coconut.persistentModelID]
        model.deleteSelected(in: [olive, coconut])
        let message = model.deleteBlockedMessage

        #expect(message.contains("Olive Oil"))
        #expect(message.contains("Coconut Oil"))
    }
}
