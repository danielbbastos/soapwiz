import Foundation
import SwiftData

struct DataSeeder {
    struct QuantityUnitSeed: Decodable {
        let name: String
        let symbol: String
    }

    static func seed(into context: ModelContext) {
        guard
            let url = Bundle.main.url(forResource: "DefaultQuantityUnits", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let seeds = try? JSONDecoder().decode([QuantityUnitSeed].self, from: data)
        else { return }

        seedQuantityUnits(seeds, into: context)

        #if DEBUG
        seedTestIngredients(into: context)
        #endif
    }

    static func seedQuantityUnits(_ seeds: [QuantityUnitSeed], into context: ModelContext) {
        guard let count = try? context.fetchCount(FetchDescriptor<QuantityUnit>()), count == 0 else { return }
        for seed in seeds {
            context.insert(QuantityUnit(name: seed.name, symbol: seed.symbol))
        }
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
        let batches: [BatchSeed]
    }

    private struct BatchSeed: Decodable {
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

        let units = (try? context.fetch(FetchDescriptor<QuantityUnit>())) ?? []
        let unitMap = Dictionary(uniqueKeysWithValues: units.map { ($0.symbol, $0) })

        for ingredientSeed in seed.ingredients {
            let ingredient = Ingredient(
                name: ingredientSeed.name,
                category: categoryMap[ingredientSeed.category],
                unit: unitMap[ingredientSeed.unit]
            )
            context.insert(ingredient)

            for batchSeed in ingredientSeed.batches {
                let batch = IngredientBatch(
                    provider: providerMap[batchSeed.provider],
                    dateOfPurchase: formatter.date(from: batchSeed.dateOfPurchase) ?? .now,
                    quantity: batchSeed.quantity,
                    totalPrice: batchSeed.totalPrice,
                    badge: batchSeed.badge,
                    journalCode: batchSeed.journalCode,
                    expiryDate: batchSeed.expiryDate.flatMap { formatter.date(from: $0) },
                    openingDate: batchSeed.openingDate.flatMap { formatter.date(from: $0) },
                    storageLocation: storageMap[batchSeed.storageLocation]
                )
                batch.remainingAmount = batchSeed.remainingAmount
                ingredient.batches.append(batch)
                context.insert(batch)
            }
        }
    }
}
#endif
