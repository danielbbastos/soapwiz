import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Shared helpers for the IngredientFormViewModelTests test suites.
@MainActor
protocol IngredientFormTestHelpers {}

extension IngredientFormTestHelpers {
    func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }
}
