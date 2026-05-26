import Foundation
import SwiftData

struct DataSeeder {
    static func seed(into context: ModelContext) {
        #if DEBUG
        seedTestIngredients(into: context)
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

        for ingredientSeed in seed.ingredients {
            let unitRaw = IngredientUnit.allCases
                .first { $0.rawValue.lowercased() == ingredientSeed.unit.lowercased() }?.rawValue
                ?? ingredientSeed.unit
            let ingredient = Ingredient(
                name: ingredientSeed.name,
                category: categoryMap[ingredientSeed.category],
                unit: unitRaw
            )
            ingredient.sapValue = ingredientSeed.sapValue
            ingredient.kohSapValue = ingredientSeed.kohSapValue
            ingredient.density = ingredientSeed.density
            ingredient.fattyAcidProfile = ingredientSeed.fattyAcidProfile
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
