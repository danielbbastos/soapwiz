import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Shared helpers for the ingredient unit change test suites (SW-256).
@MainActor
protocol IngredientUnitChangeTestHelpers {}

extension IngredientUnitChangeTestHelpers {
    var locale: Locale { Locale(identifier: "en_US_POSIX") }

    func makeContainer() throws -> ModelContainer {
        let schema = ModelContainerFactory.schema
        return try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
    }

    func makePurchase(quantity: Double, totalPrice: Double = 10, remaining: Double? = nil) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: quantity,
            totalPrice: totalPrice,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        if let remaining { purchase.remainingAmount = remaining }
        return purchase
    }

    func makeIngredient(
        in context: ModelContext,
        unit: String,
        quantities: [Double] = [],
        threshold: Double? = nil
    ) throws -> Ingredient {
        let ingredient = Ingredient(name: "Olive Oil", unit: unit)
        ingredient.lowStockThreshold = threshold
        context.insert(ingredient)
        for quantity in quantities {
            let purchase = makePurchase(quantity: quantity)
            context.insert(purchase)
            purchase.attach(to: ingredient)
        }
        try context.save()
        return ingredient
    }

    func approximately(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 1e-9
    }
}
