import Foundation
import SwiftData

/// Every shopping list line, oldest first, kept apart from `@Query`. Watches
/// `ShoppingListItem`.
typealias ShoppingListRows = ModelRows<ShoppingListItem>

extension ModelRows where Model == ShoppingListItem {
    convenience init(
        context: ModelContext,
        importTimeout: Duration = .seconds(120),
        pruneInterval: Duration = .seconds(1),
        fetchItems: @escaping @MainActor (ModelContext) throws -> [ShoppingListItem] = ShoppingListRows.fetchAll(in:)
    ) {
        self.init(
            context: context,
            watchedEntities: [Schema.entityName(for: ShoppingListItem.self)],
            logCategory: "shoppingList",
            importTimeout: importTimeout,
            pruneInterval: pruneInterval,
            fetch: fetchItems
        )
    }

    var items: [ShoppingListItem] { rows }

    /// Every line by creation date. Injected only so a test can count the fetches or make them fail.
    static func fetchAll(in context: ModelContext) throws -> [ShoppingListItem] {
        try context.fetch(FetchDescriptor<ShoppingListItem>(sortBy: [SortDescriptor(\ShoppingListItem.createdAt)]))
    }
}
