import Foundation
import SwiftData

@Model
final class ProductVariant {
    var formula: Formula?
    var name: String
    var size: Double
    var packagingCost: Double
    var pvpr: Double
    var pvp: Double

    var totalCostPerUnit: Double {
        guard let formula else { return packagingCost }
        let ingredientCost = formula.ingredients.reduce(0.0) { sum, fi in
            sum + fi.amountForSize(size) * fi.costPerUnit
        }
        return ingredientCost + packagingCost
    }

    var pricePerSizeUnit: Double {
        guard size > 0 else { return 0 }
        return totalCostPerUnit / size
    }

    init(name: String, size: Double, packagingCost: Double = 0, pvpr: Double = 0, pvp: Double = 0) {
        self.name = name
        self.size = size
        self.packagingCost = packagingCost
        self.pvpr = pvpr
        self.pvp = pvp
    }
}
