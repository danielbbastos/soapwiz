import Foundation
import OSLog
import SwiftData

/// The fixed sample the onboarding tour runs on: stock for one recipe, the
/// recipe, and a batch made from it, so every tab has something to show.
///
/// Not `DataSeeder`'s, which only exists in DEBUG and fills a developer's store:
/// this ships, and goes into the tour's own in-memory store only. The numbers
/// are fixed so the tour's copy can quote them (a recipe costing 5.06, a 1000 ml
/// olive oil purchase) without reading them back from the store. The batch uses
/// 360 g of olive oil, which leaves about 605 ml of it.
enum TourSample {
    private static let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "tour")

    static let recipeName = "Classic Bastille Bar"
    static let providerName = "Local supplier"
    static let lyeName = "Sodium Hydroxide (Lye)"

    /// How long before `now` the stock was bought, so the tour shows purchases
    /// from the recent past whichever day it is opened.
    static let purchaseAgeDays = 12

    private struct StockSeed {
        let ingredient: String
        let size: Double
        /// The unit the library stocks the ingredient in. A row in any other
        /// unit is skipped rather than converted, so a library change shows up
        /// as a failing test and not as an odd quantity on the tour's cards.
        let unit: String
        let price: Double
    }

    /// Sizes are round numbers in each ingredient's own unit, because the tour
    /// highlights these cards. The prices are chosen so the recipe's cost lines
    /// come to 1.35, 0.46, 0.44 and 2.28 (olive and lavender are by volume, so
    /// their prices work out through density), and its total to 5.06 with the lye.
    private static let stock: [StockSeed] = [
        StockSeed(ingredient: "Olive Oil", size: 1000, unit: "ml", price: 3.42),
        StockSeed(ingredient: "Coconut Oil", size: 1000, unit: "g", price: 4.60),
        StockSeed(ingredient: "Castor Oil", size: 500, unit: "g", price: 5.50),
        StockSeed(ingredient: "Lavender Essential Oil", size: 100, unit: "ml", price: 13.38),
        StockSeed(ingredient: lyeName, size: 1000, unit: "g", price: 7.65)
    ]

    /// The unit each stocked ingredient is expected in, for a test to hold
    /// against the library.
    static let stockUnits: [String: String] = Dictionary(
        uniqueKeysWithValues: stock.map { ($0.ingredient, $0.unit) }
    )

    private static let oils: [(name: String, percentage: Double)] = [
        ("Olive Oil", 72), ("Coconut Oil", 20), ("Castor Oil", 8)
    ]

    private static let fragrance = (name: "Lavender Essential Oil", percentage: 3.0)

    static func insert(into context: ModelContext, currencyCode: String, now: Date) {
        let settings = AppSettings.resolve(in: context)
        settings.currencyCode = currencyCode
        settings.tracksInventory = true

        let ingredients = libraryIngredients(in: context)
        insertStock(for: ingredients, into: context, now: now)
        guard let recipe = insertRecipe(from: ingredients, into: context) else {
            log.error("Tour sample has no recipe, so no batch either")
            return
        }
        context.saveLoggingFailure()

        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        model.process = .cold
        if model.create(context: context, date: now) == nil {
            log.error("Tour sample batch was not created")
        }
    }

    private static func libraryIngredients(in context: ModelContext) -> [String: Ingredient] {
        let rows = (try? context.fetch(FetchDescriptor<Ingredient>())) ?? []
        let library = rows.filter { !$0.librarySlug.isEmpty }
        return Dictionary(library.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func insertStock(
        for ingredients: [String: Ingredient],
        into context: ModelContext,
        now: Date
    ) {
        let provider = Provider(name: providerName)
        context.insert(provider)
        let calendar = Calendar.current
        let bought = calendar.date(byAdding: .day, value: -purchaseAgeDays, to: now) ?? now
        let expiry = calendar.date(byAdding: .year, value: 1, to: bought)

        for seed in stock {
            guard let ingredient = ingredients[seed.ingredient], ingredient.unit == seed.unit else { continue }
            let purchase = IngredientPurchase(
                provider: provider,
                dateOfPurchase: bought,
                quantity: seed.size,
                totalPrice: seed.price,
                badge: "",
                journalCode: "",
                expiryDate: expiry,
                openingDate: nil
            )
            context.insert(purchase)
            purchase.attach(to: ingredient)
        }
    }

    private static func insertRecipe(
        from ingredients: [String: Ingredient],
        into context: ModelContext
    ) -> Recipe? {
        var oilRows: [(ingredient: Ingredient, percentage: Double)] = []
        for oil in oils {
            guard let ingredient = ingredients[oil.name] else { return nil }
            oilRows.append((ingredient, oil.percentage))
        }

        let recipe = Recipe(
            name: recipeName,
            desc: "A skin-loving bar built on olive oil with a coconut boost for lather. "
                + "Gentle enough for daily use."
        )
        recipe.recipeKind = RecipeKind.soap.rawValue
        recipe.weightUnit = "%"
        recipe.totalOilWeight = 500
        recipe.oilWeightUnit = "g"
        recipe.lyeType = "NaOH"
        recipe.lyePurity = 99
        recipe.waterParts = 1.5
        recipe.superFat = 5
        recipe.fragrancePercentage = fragrance.percentage
        recipe.fragranceUnit = FragranceUnit.percentOfOils.rawValue
        recipe.lyeIngredient = ingredients[lyeName]
        context.insert(recipe)

        for oil in oilRows {
            let row = RecipeIngredient(ingredient: oil.ingredient, percentage: oil.percentage, role: .oil)
            row.recipe = recipe
            context.insert(row)
        }

        if let ingredient = ingredients[fragrance.name] {
            let row = RecipeIngredient(ingredient: ingredient, percentage: 0, role: .fragrance)
            row.additiveAmount = fragrance.percentage
            row.additiveUnit = FragranceUnit.percentOfOils.rawValue
            row.recipe = recipe
            context.insert(row)
        }

        let product = RecipeProduct(size: 1, unitSymbol: ProductUnit.wholeBatch.rawValue)
        product.recipe = recipe
        context.insert(product)
        return recipe
    }
}
