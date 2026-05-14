import Foundation
import SwiftData

@Model
final class ProductVariant {
    var formula: Formula?
    var name: String
    var sizeGrams: Double
    var packagingCost: Double
    var pvpr: Double
    var pvp: Double

    var totalCostPerUnit: Double {
        guard let formula else { return packagingCost }
        let ingredientCost = formula.ingredients.reduce(0.0) { sum, fi in
            sum + fi.amountForSize(sizeGrams) * fi.costPerUnit
        }
        return ingredientCost + packagingCost
    }

    var eurPerGram: Double {
        guard sizeGrams > 0 else { return 0 }
        return totalCostPerUnit / sizeGrams
    }

    init(name: String, sizeGrams: Double, packagingCost: Double = 0, pvpr: Double = 0, pvp: Double = 0) {
        self.name = name
        self.sizeGrams = sizeGrams
        self.packagingCost = packagingCost
        self.pvpr = pvpr
        self.pvp = pvp
    }
}
