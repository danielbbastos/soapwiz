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
    }

    static func seedQuantityUnits(_ seeds: [QuantityUnitSeed], into context: ModelContext) {
        guard let count = try? context.fetchCount(FetchDescriptor<QuantityUnit>()), count == 0 else { return }
        for seed in seeds {
            context.insert(QuantityUnit(name: seed.name, symbol: seed.symbol))
        }
    }
}
