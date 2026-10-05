import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Ingredient picker choices")
@MainActor
struct IngredientPickerChoicesTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    private func choices(
        _ ingredients: [Ingredient],
        searchText: String = "",
        category: IngredientCategory? = nil,
        inStockOnly: Bool = false
    ) -> [String] {
        IngredientPickerFilter(searchText: searchText, category: category, inStockOnly: inStockOnly)
            .choices(from: ingredients, allowedRoles: nil, includesUnroled: false)
            .map(\.name)
    }

    // MARK: - Favourites

    @Test func choices_Favourites_ComeFirstKeepingArrivalOrder() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = ["Almond", "Babassu", "Coconut", "Olive"].map { Ingredient.mock(name: $0, in: ctx) }
        ingredients[1].isFavorite = true
        ingredients[3].isFavorite = true

        #expect(choices(ingredients) == ["Babassu", "Olive", "Almond", "Coconut"])
    }

    @Test func choices_NoFavourites_KeepsArrivalOrder() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredients = ["Almond", "Babassu", "Coconut"].map { Ingredient.mock(name: $0, in: ctx) }

        #expect(choices(ingredients) == ["Almond", "Babassu", "Coconut"])
    }

    @Test func choices_EmptyInventory_ReturnsEmpty() {
        #expect(choices([]).isEmpty)
    }

    // MARK: - In stock

    @Test func choices_InStockOnly_KeepsRowsWithStockIncludingLowStock() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let plenty = Ingredient.mock(name: "Olive", in: ctx, remaining: [500])
        let low = Ingredient.mock(name: "Shea", in: ctx, remaining: [5])
        low.lowStockThreshold = 100
        let empty = Ingredient.mock(name: "Cocoa", in: ctx, remaining: [0])
        let neverBought = Ingredient.mock(name: "Castor", in: ctx)

        #expect(low.isLowStock)
        #expect(choices([plenty, low, empty, neverBought], inStockOnly: true) == ["Olive", "Shea"])
    }

    @Test func choices_InStockOnly_SumsAcrossPurchases() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient.mock(name: "Olive", in: ctx, remaining: [0, 20])

        #expect(choices([ingredient], inStockOnly: true) == ["Olive"])
    }

    @Test func choices_InStockOff_KeepsOutOfStockRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let empty = Ingredient.mock(name: "Cocoa", in: ctx, remaining: [0])

        #expect(choices([empty]) == ["Cocoa"])
    }

    @Test func choices_InStockOnlyWithCategory_AppliesBoth() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        let fragrances = IngredientCategory(name: IngredientCategory.Name.fragrances)
        ctx.insert(oils)
        ctx.insert(fragrances)
        let stockedOil = Ingredient.mock(name: "Olive", category: oils, in: ctx, remaining: [100])
        let emptyOil = Ingredient.mock(name: "Castor", category: oils, in: ctx, remaining: [0])
        let stockedFragrance = Ingredient.mock(name: "Lavender", category: fragrances, in: ctx, remaining: [50])

        let result = choices([emptyOil, stockedFragrance, stockedOil], category: oils, inStockOnly: true)

        #expect(result == ["Olive"])
    }

    @Test func choices_InStockOnlyWithSearch_AppliesBoth() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient.mock(name: "Olive Oil", in: ctx, remaining: [100])
        let coconut = Ingredient.mock(name: "Coconut Oil", in: ctx, remaining: [0])
        let shea = Ingredient.mock(name: "Shea Butter", in: ctx, remaining: [100])

        #expect(choices([coconut, olive, shea], searchText: "oil", inStockOnly: true) == ["Olive Oil"])
    }

    @Test func choices_InStockOnly_FavouritesStillFirst() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let almond = Ingredient.mock(name: "Almond", in: ctx, remaining: [10])
        let olive = Ingredient.mock(name: "Olive", in: ctx, remaining: [10])
        let favouriteEmpty = Ingredient.mock(name: "Babassu", in: ctx, remaining: [0])
        olive.isFavorite = true
        favouriteEmpty.isFavorite = true

        #expect(choices([almond, favouriteEmpty, olive], inStockOnly: true) == ["Olive", "Almond"])
    }

    // MARK: - Hidden

    @Test func choices_HiddenFavouriteInStock_StaysExcluded() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let hidden = Ingredient.mock(name: "Olive", in: ctx, remaining: [100])
        hidden.isHidden = true
        hidden.isFavorite = true

        #expect(choices([hidden]).isEmpty)
        #expect(choices([hidden], inStockOnly: true).isEmpty)
    }

    // MARK: - Lye and neutraliser picker

    @Test func candidates_Favourites_ComeFirstEachGroupByName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lyes = IngredientCategory(name: IngredientCategory.Name.lyes)
        ctx.insert(lyes)
        let koh = Ingredient.mock(name: "Potassium Hydroxide", category: lyes, in: ctx)
        let naoh = Ingredient.mock(name: "Sodium Hydroxide", category: lyes, in: ctx)
        let flakes = Ingredient.mock(name: "NaOH Flakes", category: lyes, in: ctx)
        naoh.isFavorite = true

        let result = CategoryIngredientPickerView.candidates(
            from: [koh, naoh, flakes],
            category: IngredientCategory.Name.lyes,
            selected: nil
        )

        #expect(result.map(\.name) == ["Sodium Hydroxide", "NaOH Flakes", "Potassium Hydroxide"])
    }

    @Test func candidates_HiddenSelectedFavourite_StaysListedFirst() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lyes = IngredientCategory(name: IngredientCategory.Name.lyes)
        ctx.insert(lyes)
        let koh = Ingredient.mock(name: "Potassium Hydroxide", category: lyes, in: ctx)
        let naoh = Ingredient.mock(name: "Sodium Hydroxide", category: lyes, in: ctx)
        naoh.isHidden = true
        naoh.isFavorite = true

        let result = CategoryIngredientPickerView.candidates(
            from: [koh, naoh],
            category: IngredientCategory.Name.lyes,
            selected: naoh
        )

        #expect(result.map(\.name) == ["Sodium Hydroxide", "Potassium Hydroxide"])
    }
}

extension Ingredient {
    fileprivate static func mock(
        name: String,
        category: IngredientCategory? = nil,
        in context: ModelContext,
        remaining: [Double] = []
    ) -> Ingredient {
        let ingredient = Ingredient(name: name, category: category, unit: "g")
        context.insert(ingredient)
        for amount in remaining {
            let purchase = IngredientPurchase(
                dateOfPurchase: .now,
                quantity: 1000,
                totalPrice: 10,
                badge: "",
                journalCode: "",
                expiryDate: nil,
                openingDate: nil
            )
            purchase.remainingAmount = amount
            context.insert(purchase)
            purchase.attach(to: ingredient)
        }
        return ingredient
    }
}
