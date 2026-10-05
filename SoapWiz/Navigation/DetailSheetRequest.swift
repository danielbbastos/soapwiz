import Foundation
import SwiftData

/// A sheet opened from a recipe's or an ingredient's detail screen, set on
/// `AppNavigation.detailSheetRequest` and presented by `ContentView` above the
/// tabs (SW-218). A sheet the detail presented itself was dismissed whenever
/// the window crossed the list-beside-detail width, since the detail moves to
/// the other stack then, and it took whatever the user had typed with it.
///
/// Presented from up there, the sheet no longer closes with its detail, so it
/// has to close itself when its model leaves the store: deleted on another
/// device, or merged away as a duplicate. Reading the deleted model traps.
/// `targetID` is read when the request is made, because by then nothing can
/// be read off that model.
struct DetailSheetRequest: Identifiable {
    enum Kind {
        case createBatch(Recipe)
        case addPurchase(Ingredient)
        case editIngredient(Ingredient)
    }

    let id = UUID()
    let kind: Kind
    let targetID: PersistentIdentifier

    static func createBatch(_ recipe: Recipe) -> DetailSheetRequest {
        DetailSheetRequest(kind: .createBatch(recipe), targetID: recipe.persistentModelID)
    }

    static func addPurchase(_ ingredient: Ingredient) -> DetailSheetRequest {
        DetailSheetRequest(kind: .addPurchase(ingredient), targetID: ingredient.persistentModelID)
    }

    static func editIngredient(_ ingredient: Ingredient) -> DetailSheetRequest {
        DetailSheetRequest(kind: .editIngredient(ingredient), targetID: ingredient.persistentModelID)
    }

    /// Whether the sheet's model is still in the store. A duplicate merge counts
    /// as gone too: the forms read the captured row directly, and following the
    /// surviving copy would mean rebuilding them, which loses the input anyway.
    func isTargetStored(in context: ModelContext) -> Bool {
        switch kind {
        case .createBatch:
            Self.hasMatch(FetchDescriptor(predicate: Self.recipe(id: targetID)), in: context)
        case .addPurchase, .editIngredient:
            Self.hasMatch(FetchDescriptor(predicate: Self.ingredient(id: targetID)), in: context)
        }
    }

    /// The predicates `DetailSheetHost` queries, so it hears of the delete the
    /// moment it lands.
    static func recipe(id: PersistentIdentifier) -> Predicate<Recipe> {
        #Predicate { $0.persistentModelID == id }
    }

    static func ingredient(id: PersistentIdentifier) -> Predicate<Ingredient> {
        #Predicate { $0.persistentModelID == id }
    }

    private static func hasMatch<Model: PersistentModel>(
        _ descriptor: FetchDescriptor<Model>, in context: ModelContext
    ) -> Bool {
        ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}
