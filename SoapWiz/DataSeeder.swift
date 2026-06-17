import Foundation
import SwiftData

struct DataSeeder {
    static func seed(into context: ModelContext) {
        #if DEBUG
        seedTestIngredients(into: context)
        seedTestRecipes(into: context)
        #endif
    }
}

#if DEBUG
extension DataSeeder {
    private struct TestDataSeed: Decodable {
        let categories: [String]
        let providers: [String]
        let storageLocations: [String]
        let ingredients: [IngredientSeed]
    }

    private struct IngredientSeed: Decodable {
        let name: String
        let category: String
        let unit: String
        let sapValue: Double?
        let kohSapValue: Double?
        let density: Double?
        let fattyAcidProfile: FattyAcidProfile?
        let purchases: [PurchaseSeed]
    }

    private struct PurchaseSeed: Decodable {
        let provider: String
        let dateOfPurchase: String
        let quantity: Double
        let totalPrice: Double
        let badge: String
        let journalCode: String
        let expiryDate: String?
        let openingDate: String?
        let remainingAmount: Double
        let storageLocation: String
    }

    private struct RecipeSeed {
        let name: String
        let desc: String
        let totalOilWeight: Double
        /// Oil name → percentage of the oil weight. Must sum to 100.
        let oils: [(String, Double)]
        /// Fragrance name → "% of oils" amount.
        let fragrance: (String, Double)?
    }

    private static let recipeSeeds: [RecipeSeed] = [
        RecipeSeed(
            name: "Classic Bastille Bar",
            desc: "A skin-loving bar built on olive oil with a coconut boost for lather. Gentle enough for daily use.",
            totalOilWeight: 500,
            oils: [("Olive Oil", 72), ("Coconut Oil", 20), ("Castor Oil", 8)],
            fragrance: ("Lavender Essential Oil", 3)
        ),
        RecipeSeed(
            name: "Everyday Kitchen Bar",
            desc: "A sturdy unscented workhorse bar from pantry-staple oils. Cleans hands after cooking or gardening.",
            totalOilWeight: 600,
            oils: [("Palm Oil", 35), ("Coconut Oil", 25), ("Sunflower Oil", 20),
                   ("Rice Bran Oil", 10), ("Sweet Almond Oil", 10)],
            fragrance: nil
        ),
        RecipeSeed(
            name: "Silky Butter Bar",
            desc: "Shea and cocoa butters for a creamy, conditioning lather with a fresh peppermint finish.",
            totalOilWeight: 500,
            oils: [("Olive Oil", 40), ("Shea Butter", 25), ("Coconut Oil", 20), ("Cocoa Butter", 15)],
            fragrance: ("Peppermint Essential Oil", 2)
        ),
        RecipeSeed(
            name: "Pure Castile",
            desc: "The traditional single-oil soap: 100% olive, unscented, famously mild after a long cure.",
            totalOilWeight: 450,
            oils: [("Olive Oil", 100)],
            fragrance: nil
        )
    ]

    static func seedTestRecipes(into context: ModelContext) {
        guard let count = try? context.fetchCount(FetchDescriptor<Recipe>()), count == 0 else { return }
        for seed in recipeSeeds {
            insertRecipe(seed, into: context)
        }
    }

    private static func insertRecipe(_ seed: RecipeSeed, into context: ModelContext) {
        func ingredient(named name: String) -> Ingredient? {
            let predicate = #Predicate<Ingredient> { $0.name == name }
            return try? context.fetch(FetchDescriptor(predicate: predicate)).first
        }

        let recipe = Recipe(name: seed.name, desc: seed.desc)
        recipe.weightUnit = "%"
        recipe.totalOilWeight = seed.totalOilWeight
        recipe.oilWeightUnit = "g"
        recipe.lyeType = "NaOH"
        recipe.lyePurity = 99
        recipe.waterParts = 1.5
        recipe.superFat = 5
        recipe.fragrancePercentage = seed.fragrance?.1 ?? 0
        recipe.lyeIngredient = ingredient(named: "Sodium Hydroxide (Lye)")
        context.insert(recipe)

        for (name, pct) in seed.oils {
            guard let ing = ingredient(named: name) else { continue }
            let recipeIngredient = RecipeIngredient(ingredient: ing, percentage: pct, role: .oil)
            recipeIngredient.recipe = recipe
            context.insert(recipeIngredient)
        }

        if let (fragranceName, pct) = seed.fragrance, let ing = ingredient(named: fragranceName) {
            let recipeIngredient = RecipeIngredient(ingredient: ing, percentage: 0, role: .fragrance)
            recipeIngredient.additiveAmount = pct
            recipeIngredient.additiveUnit = "% of oils"
            recipeIngredient.recipe = recipe
            context.insert(recipeIngredient)
        }

        let product = RecipeProduct(size: 1, unitSymbol: ProductUnit.wholeBatch.rawValue)
        product.recipe = recipe
        context.insert(product)
    }

    static func seedTestIngredients(into context: ModelContext) {
        guard let count = try? context.fetchCount(FetchDescriptor<Ingredient>()), count == 0 else { return }

        guard
            let url = Bundle.main.url(forResource: "TestIngredients", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let seed = try? JSONDecoder().decode(TestDataSeed.self, from: data)
        else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var categoryMap: [String: IngredientCategory] = [:]
        for name in seed.categories {
            let cat = IngredientCategory(name: name)
            context.insert(cat)
            categoryMap[name] = cat
        }

        var providerMap: [String: Provider] = [:]
        for name in seed.providers {
            let provider = Provider(name: name)
            context.insert(provider)
            providerMap[name] = provider
        }

        var storageMap: [String: StorageLocation] = [:]
        for name in seed.storageLocations {
            let loc = StorageLocation(name: name)
            context.insert(loc)
            storageMap[name] = loc
        }

        let lookups = SeedLookups(
            categories: categoryMap,
            providers: providerMap,
            storage: storageMap,
            formatter: formatter
        )
        for ingredientSeed in seed.ingredients {
            insertIngredient(ingredientSeed, into: context, lookups: lookups)
        }
    }

    /// Resolved lookup tables and date parser shared across ingredient inserts.
    private struct SeedLookups {
        let categories: [String: IngredientCategory]
        let providers: [String: Provider]
        let storage: [String: StorageLocation]
        let formatter: DateFormatter
    }

    private static func insertIngredient(
        _ ingredientSeed: IngredientSeed,
        into context: ModelContext,
        lookups: SeedLookups
    ) {
        let unitRaw = IngredientUnit.allCases
            .first { $0.rawValue.lowercased() == ingredientSeed.unit.lowercased() }?.rawValue
            ?? ingredientSeed.unit
        let ingredient = Ingredient(
            name: ingredientSeed.name,
            category: lookups.categories[ingredientSeed.category],
            unit: unitRaw
        )
        ingredient.sapValue = ingredientSeed.sapValue
        ingredient.kohSapValue = ingredientSeed.kohSapValue
        ingredient.density = ingredientSeed.density
        ingredient.fattyAcidProfile = ingredientSeed.fattyAcidProfile
        context.insert(ingredient)

        for purchaseSeed in ingredientSeed.purchases {
            let purchase = IngredientPurchase(
                provider: lookups.providers[purchaseSeed.provider],
                dateOfPurchase: lookups.formatter.date(from: purchaseSeed.dateOfPurchase) ?? .now,
                quantity: purchaseSeed.quantity,
                totalPrice: purchaseSeed.totalPrice,
                badge: purchaseSeed.badge,
                journalCode: purchaseSeed.journalCode,
                expiryDate: purchaseSeed.expiryDate.flatMap { lookups.formatter.date(from: $0) },
                openingDate: purchaseSeed.openingDate.flatMap { lookups.formatter.date(from: $0) },
                storageLocation: lookups.storage[purchaseSeed.storageLocation]
            )
            purchase.remainingAmount = purchaseSeed.remainingAmount
            ingredient.purchases.append(purchase)
            context.insert(purchase)
        }
    }
}
#endif
