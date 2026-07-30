import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Covers the to-many relationship conversion that unblocked CloudKit mirroring:
/// every array is stored as an optional under a `…Storage` name and exposed as a
/// non-optional accessor. The accessor's setter means `append` round-trips the
/// whole array through the relationship, so the delete rules are re-asserted here
/// rather than assumed.
@Suite("CloudKit to-many relationships", .serialized)
@MainActor
struct CloudKitRelationshipTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    // MARK: - The CloudKit invariant itself

    /// The constraint `NSPersistentCloudKitContainer` enforces at container init.
    /// Asserting it against the schema catches a regression without needing an
    /// iCloud account or entitlement, so it runs in CI.
    @Test func schema_EveryToManyRelationship_IsOptional() {
        let offenders = ModelContainerFactory.schema.entities.flatMap { entity in
            entity.relationships
                .filter { !$0.isToOneRelationship && !$0.isOptional }
                .map { "\(entity.name): \($0.name)" }
        }

        #expect(offenders.isEmpty, "Non-optional to-many relationships: \(offenders.sorted())")
    }

    @Test func schema_EveryToOneRelationship_IsOptional() {
        let offenders = ModelContainerFactory.schema.entities.flatMap { entity in
            entity.relationships
                .filter { $0.isToOneRelationship && !$0.isOptional }
                .map { "\(entity.name): \($0.name)" }
        }

        #expect(offenders.isEmpty, "Non-optional to-one relationships: \(offenders.sorted())")
    }

    @Test func schema_NoRelationship_UsesDenyDeleteRule() {
        let offenders = ModelContainerFactory.schema.entities.flatMap { entity in
            entity.relationships
                .filter { $0.deleteRule == .deny }
                .map { "\(entity.name): \($0.name)" }
        }

        #expect(offenders.isEmpty, "Relationships using .deny: \(offenders.sorted())")
    }

    // MARK: - Accessor semantics

    @Test func accessor_NewModel_ReturnsEmptyNotNil() {
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")

        #expect(ingredient.purchases.isEmpty)
        #expect(ingredient.recipeIngredients.isEmpty)
        #expect(ingredient.batchLineItems.isEmpty)
        #expect(ingredient.recipesUsingAsLye.isEmpty)
        #expect(ingredient.recipesUsingAsKOHLye.isEmpty)
    }

    @Test func accessor_StorageIsNil_ReadsAsEmpty() {
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.purchasesStorage = nil

        #expect(ingredient.purchases.isEmpty)
        #expect(ingredient.totalRemaining == 0)
        #expect(ingredient.hasExpiredPurchase == false)
        #expect(ingredient.nearestUpcomingExpiry == nil)
    }

    @Test func accessor_AppendThroughSetter_Persists() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)
        let purchase = IngredientPurchase.mock(quantity: 500)
        ctx.insert(purchase)
        ingredient.purchases.append(purchase)
        try ctx.save()

        let fetched = try #require(try ctx.fetch(FetchDescriptor<Ingredient>()).first)
        #expect(fetched.purchases.count == 1)
        #expect(fetched.purchasesStorage?.count == 1)
        #expect(fetched.totalRemaining == 500)
    }

    /// The setter assigns the whole array back. Appending a second element must
    /// not drop the first, and must not cascade-delete it as a removed member.
    @Test func accessor_RepeatedAppends_KeepEveryElement() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)

        for quantity in [100.0, 200.0, 300.0] {
            let purchase = IngredientPurchase.mock(quantity: quantity)
            ctx.insert(purchase)
            ingredient.purchases.append(purchase)
        }
        try ctx.save()

        #expect(ingredient.purchases.count == 3)
        #expect(ingredient.totalRemaining == 600)
        #expect(try ctx.fetch(FetchDescriptor<IngredientPurchase>()).count == 3)
    }

    /// Populating from the inverse to-one side is how most of the app builds
    /// these relationships, and it must still surface through the accessor.
    @Test func accessor_PopulatedFromInverse_ReadsThroughAccessor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)
        let purchase = IngredientPurchase.mock(quantity: 250)
        purchase.ingredient = ingredient
        ctx.insert(purchase)
        try ctx.save()

        #expect(ingredient.purchases.count == 1)
        #expect(ingredient.totalRemaining == 250)
    }

    @Test func accessor_AssigningWholeArray_ReplacesContents() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)
        let first = IngredientPurchase.mock(quantity: 100)
        let second = IngredientPurchase.mock(quantity: 200)
        ctx.insert(first)
        ctx.insert(second)

        ingredient.purchases = [first, second]
        try ctx.save()
        #expect(ingredient.purchases.count == 2)

        ingredient.purchases = [first]
        try ctx.save()
        #expect(ingredient.purchases.count == 1)
        #expect(ingredient.totalRemaining == 100)
    }

    // MARK: - Cascade delete rules

    @Test func deleteIngredient_CascadesToPurchases() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)
        let purchase = IngredientPurchase.mock(quantity: 500)
        ctx.insert(purchase)
        ingredient.purchases.append(purchase)
        try ctx.save()

        ctx.delete(ingredient)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<IngredientPurchase>()).isEmpty)
    }

    @Test func deleteIngredient_CascadesToRecipeIngredients() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(ingredient)
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: ingredient, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()

        ctx.delete(ingredient)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<RecipeIngredient>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Recipe>()).count == 1)
    }

    @Test func deleteRecipe_CascadesToIngredientsAndProducts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(ingredient)
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: ingredient, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        let product = RecipeProduct(size: 100, unitSymbol: "g")
        product.recipe = recipe
        ctx.insert(product)
        try ctx.save()

        ctx.delete(recipe)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<RecipeIngredient>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<RecipeProduct>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).count == 1)
    }

    @Test func deleteBatch_CascadesToLineItems() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)
        let batch = Batch(recipe: nil, recipeName: "Bastille", batchCount: 1)
        ctx.insert(batch)
        let lineItem = BatchLineItem(
            ingredient: ingredient,
            ingredientName: "Olive Oil",
            amountConsumed: 100,
            unit: "g",
            cost: 1,
            draws: []
        )
        lineItem.batch = batch
        ctx.insert(lineItem)
        try ctx.save()

        ctx.delete(batch)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<BatchLineItem>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).count == 1)
    }

    // MARK: - Nullify delete rules — history outlives its sources

    @Test func deleteIngredient_NullifiesBatchLineItemsAndKeepsHistory() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)
        let batch = Batch(recipe: nil, recipeName: "Bastille", batchCount: 1)
        ctx.insert(batch)
        let lineItem = BatchLineItem(
            ingredient: ingredient,
            ingredientName: "Olive Oil",
            amountConsumed: 100,
            unit: "g",
            cost: 1,
            draws: []
        )
        lineItem.batch = batch
        ctx.insert(lineItem)
        try ctx.save()

        ctx.delete(ingredient)
        try ctx.save()

        let lineItems = try ctx.fetch(FetchDescriptor<BatchLineItem>())
        #expect(lineItems.count == 1)
        #expect(lineItems.first?.ingredient == nil)
        #expect(lineItems.first?.ingredientName == "Olive Oil")
        #expect(batch.lineItems.count == 1)
    }

    @Test func deleteRecipe_NullifiesBatchesAndKeepsHistory() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Bastille")
        ctx.insert(recipe)
        let batch = Batch(recipe: recipe, recipeName: "Bastille", batchCount: 1)
        ctx.insert(batch)
        try ctx.save()
        #expect(recipe.batches.count == 1)

        ctx.delete(recipe)
        try ctx.save()

        let batches = try ctx.fetch(FetchDescriptor<Batch>())
        #expect(batches.count == 1)
        #expect(batches.first?.recipe == nil)
        #expect(batches.first?.recipeName == "Bastille")
    }

    @Test func deleteCategory_NullifiesIngredientsAndKeepsThem() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let category = IngredientCategory(name: IngredientCategory.Name.oils)
        ctx.insert(category)
        let ingredient = Ingredient(name: "Olive Oil", category: category, unit: "g")
        ctx.insert(ingredient)
        try ctx.save()
        #expect(category.ingredients.count == 1)

        ctx.delete(category)
        try ctx.save()

        let ingredients = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(ingredients.count == 1)
        #expect(ingredients.first?.category == nil)
    }

    @Test func deleteProvider_NullifiesPurchasesAndKeepsThem() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let provider = Provider(name: "Soap Supplies")
        ctx.insert(provider)
        let purchase = IngredientPurchase.mock(quantity: 500)
        purchase.provider = provider
        ctx.insert(purchase)
        try ctx.save()
        #expect(provider.purchases.count == 1)

        ctx.delete(provider)
        try ctx.save()

        let purchases = try ctx.fetch(FetchDescriptor<IngredientPurchase>())
        #expect(purchases.count == 1)
        #expect(purchases.first?.provider == nil)
    }

    @Test func deleteStorageLocation_NullifiesPurchasesAndKeepsThem() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let location = StorageLocation(name: "Shelf A")
        ctx.insert(location)
        let purchase = IngredientPurchase.mock(quantity: 500)
        purchase.storageLocation = location
        ctx.insert(purchase)
        try ctx.save()
        #expect(location.purchases.count == 1)

        ctx.delete(location)
        try ctx.save()

        let purchases = try ctx.fetch(FetchDescriptor<IngredientPurchase>())
        #expect(purchases.count == 1)
        #expect(purchases.first?.storageLocation == nil)
    }

    // MARK: - Filtering a to-many from a fetch

    /// The supported way to filter on an optional to-many. A `#Predicate` that
    /// unwraps the storage property inline fails at fetch time with "to-many key
    /// not allowed here"; wrapping the traversal in an `#Expression` lowers it
    /// into a form the store accepts. Referenced from
    /// `ModelContainerFactory.schema`.
    @Test func fetchFiltersOnToManyViaExpression() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let inStock = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(inStock)
        let stocked = IngredientPurchase.mock(quantity: 500)
        ctx.insert(stocked)
        inStock.purchases.append(stocked)

        let depleted = Ingredient(name: "Coconut Oil", unit: "g")
        ctx.insert(depleted)
        let drained = IngredientPurchase.mock(quantity: 500)
        drained.remainingAmount = 0
        ctx.insert(drained)
        depleted.purchases.append(drained)

        let never = Ingredient(name: "Castor Oil", unit: "g")
        ctx.insert(never)
        try ctx.save()

        let hasStock = #Expression<Ingredient, Bool> { ingredient in
            ingredient.purchasesStorage?.contains { $0.remainingAmount > 0 } ?? false
        }
        let descriptor = FetchDescriptor<Ingredient>(
            predicate: #Predicate { hasStock.evaluate($0) }
        )

        let matches = try ctx.fetch(descriptor)
        #expect(matches.map(\.name) == ["Olive Oil"])
    }
}
