import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Covers the behaviour introduced by the CloudKit-compatibility schema pass:
/// the lye relationships now declare inverses, and `RecipeIngredient.ingredient`
/// is optional, so readers must tolerate a line item pointing at nothing.
@Suite("CloudKit schema compatibility", .serialized)
@MainActor
struct CloudKitSchemaCompatibilityTests {

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

    // MARK: - Lye relationship inverses

    @Test func lyeIngredient_SettingLink_PopulatesInverse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lye = Ingredient(name: "Sodium Hydroxide", unit: "g")
        let recipe = Recipe(name: "Bastille")
        recipe.lyeIngredient = lye
        ctx.insert(recipe)
        ctx.insert(lye)
        try ctx.save()

        #expect(lye.recipesUsingAsLye.count == 1)
        #expect(lye.recipesUsingAsLye.first?.name == "Bastille")
        #expect(lye.recipesUsingAsKOHLye.isEmpty)
    }

    @Test func kohLyeIngredient_SettingLink_PopulatesInverse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let koh = Ingredient(name: "Potassium Hydroxide", unit: "g")
        let recipe = Recipe(name: "Liquid Soap")
        recipe.kohLyeIngredient = koh
        ctx.insert(recipe)
        ctx.insert(koh)
        try ctx.save()

        #expect(koh.recipesUsingAsKOHLye.count == 1)
        #expect(koh.recipesUsingAsLye.isEmpty)
    }

    @Test func lyeIngredient_SharedAcrossRecipes_InverseHoldsAll() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lye = Ingredient(name: "Sodium Hydroxide", unit: "g")
        for name in ["Bastille", "Castile", "Coconut Bar"] {
            let recipe = Recipe(name: name)
            recipe.lyeIngredient = lye
            ctx.insert(recipe)
        }
        ctx.insert(lye)
        try ctx.save()

        #expect(lye.recipesUsingAsLye.count == 3)
    }

    @Test func deleteIngredient_UsedAsLye_NullifiesLinkAndKeepsRecipe() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lye = Ingredient(name: "Sodium Hydroxide", unit: "g")
        let recipe = Recipe(name: "Bastille")
        recipe.lyeIngredient = lye
        ctx.insert(recipe)
        ctx.insert(lye)
        try ctx.save()

        ctx.delete(lye)
        try ctx.save()

        let recipes = try ctx.fetch(FetchDescriptor<Recipe>())
        #expect(recipes.count == 1)
        #expect(recipes.first?.lyeIngredient == nil)
    }

    /// The explicit `@Relationship(deleteRule: .nullify)` used to sit on
    /// `Recipe.lyeIngredient`; it now lives on the `Ingredient` side. Deleting a
    /// recipe must still leave the lye ingredient — and its stock — untouched.
    @Test func deleteRecipe_WithLyeIngredients_KeepsIngredientsAlive() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let naoh = Ingredient(name: "Sodium Hydroxide", unit: "g")
        let koh = Ingredient(name: "Potassium Hydroxide", unit: "g")
        let recipe = Recipe(name: "Hybrid Bar")
        recipe.lyeIngredient = naoh
        recipe.kohLyeIngredient = koh
        ctx.insert(recipe)
        ctx.insert(naoh)
        ctx.insert(koh)
        try ctx.save()

        ctx.delete(recipe)
        try ctx.save()

        let ingredients = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(ingredients.count == 2)
        #expect(try ctx.fetch(FetchDescriptor<Recipe>()).isEmpty)
        #expect(naoh.recipesUsingAsLye.isEmpty)
        #expect(koh.recipesUsingAsKOHLye.isEmpty)
    }

    @Test func deleteIngredient_UsedAsKOHLye_NullifiesLinkAndKeepsRecipe() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let koh = Ingredient(name: "Potassium Hydroxide", unit: "g")
        let recipe = Recipe(name: "Liquid Soap")
        recipe.kohLyeIngredient = koh
        ctx.insert(recipe)
        ctx.insert(koh)
        try ctx.save()

        ctx.delete(koh)
        try ctx.save()

        let recipes = try ctx.fetch(FetchDescriptor<Recipe>())
        #expect(recipes.count == 1)
        #expect(recipes.first?.kohLyeIngredient == nil)
    }

    // MARK: - Optional RecipeIngredient.ingredient

    @Test func loadRecipe_LineItemWithNilIngredient_IsDroppedFromOilDrafts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(recipe)
        ctx.insert(olive)

        let good = RecipeIngredient(ingredient: olive, percentage: 70, role: .oil)
        good.recipe = recipe
        ctx.insert(good)

        let orphan = RecipeIngredient(ingredient: nil, percentage: 30, role: .oil)
        orphan.recipe = recipe
        ctx.insert(orphan)
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.oilDrafts.count == 1)
        #expect(model.oilDrafts.first?.ingredient.name == "Olive Oil")
    }

    @Test func loadRecipe_AdditiveAndFragranceWithNilIngredient_AreDropped() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Bastille")
        ctx.insert(recipe)

        for role in [RecipeIngredientRole.additive, .fragrance] {
            let orphan = RecipeIngredient(ingredient: nil, percentage: 0, role: role)
            orphan.recipe = recipe
            ctx.insert(orphan)
        }
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.additiveDrafts.isEmpty)
        #expect(model.fragranceDrafts.isEmpty)
    }

    @Test func loadRecipe_AllLineItemsValid_KeepsEveryDraft() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let coconut = Ingredient(name: "Coconut Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(recipe)
        ctx.insert(olive)
        ctx.insert(coconut)

        for (ingredient, pct) in [(olive, 70.0), (coconut, 30.0)] {
            let line = RecipeIngredient(ingredient: ingredient, percentage: pct, role: .oil)
            line.recipe = recipe
            ctx.insert(line)
        }
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.oilDrafts.count == 2)
    }

    @Test func exportBackup_LineItemWithNilIngredient_IsOmitted() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(recipe)
        ctx.insert(olive)

        let good = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
        good.recipe = recipe
        ctx.insert(good)

        let orphan = RecipeIngredient(ingredient: nil, percentage: 0, role: .oil)
        orphan.recipe = recipe
        ctx.insert(orphan)
        try ctx.save()

        let backup = try BackupService.makeBackup(from: ctx)
        let exported = try #require(backup.recipes.first)

        #expect(exported.ingredients.count == 1)
        #expect(exported.ingredients.first?.percentage == 100)
    }

    // MARK: - Surfacing and preserving unresolved line items

    @Test func loadRecipe_NoNilIngredients_ReportsNoUnresolvedLineItems() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(recipe)
        ctx.insert(olive)

        let good = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
        good.recipe = recipe
        ctx.insert(good)
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.unresolvedLineItemCount == 0)
    }

    @Test func loadRecipe_NilIngredients_CountsThemAcrossEveryRole() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Bastille")
        ctx.insert(recipe)

        for role in [RecipeIngredientRole.oil, .additive, .fragrance] {
            let orphan = RecipeIngredient(ingredient: nil, percentage: 0, role: role)
            orphan.recipe = recipe
            ctx.insert(orphan)
        }
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.unresolvedLineItemCount == 3)
    }

    @Test func saveRecipe_LineItemWithNilIngredient_IsPreserved() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(recipe)
        ctx.insert(olive)

        let good = RecipeIngredient(ingredient: olive, percentage: 70, role: .oil)
        good.recipe = recipe
        ctx.insert(good)

        let orphan = RecipeIngredient(ingredient: nil, percentage: 30, role: .oil)
        orphan.recipe = recipe
        ctx.insert(orphan)
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.save(context: ctx)
        try ctx.save()

        let lineItems = try ctx.fetch(FetchDescriptor<RecipeIngredient>())
        #expect(lineItems.count == 2)
        #expect(lineItems.count { $0.ingredient == nil } == 1)
        #expect(lineItems.first { $0.ingredient == nil }?.percentage == 30)
    }

    @Test func saveRecipe_LineItemWithNilIngredient_StillRebuildsResolvableRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let coconut = Ingredient(name: "Coconut Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(recipe)
        ctx.insert(olive)
        ctx.insert(coconut)

        let good = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
        good.recipe = recipe
        ctx.insert(good)

        let orphan = RecipeIngredient(ingredient: nil, percentage: 0, role: .additive)
        orphan.recipe = recipe
        ctx.insert(orphan)
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.addOil(coconut)
        model.save(context: ctx)
        try ctx.save()

        let resolved = recipe.ingredients.compactMap(\.ingredient).map(\.name).sorted()
        #expect(resolved == ["Coconut Oil", "Olive Oil"])
        #expect(recipe.ingredients.count { $0.ingredient == nil } == 1)
    }
}

@Suite("Model container factory")
@MainActor
struct ModelContainerFactoryTests {

    @Test func schema_RegistersEveryPersistedModel() {
        let registered = Set(ModelContainerFactory.schema.entities.map(\.name))
        let expected: Set = [
            "Ingredient", "IngredientPurchase", "IngredientCategory",
            "StorageLocation", "Provider",
            "Recipe", "RecipeIngredient", "RecipeProduct",
            "Batch", "BatchLineItem", "AppSettings"
        ]

        #expect(registered == expected)
    }
}
