import Foundation
import OSLog
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

    private static let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "navigation")

    static func createBatch(_ recipe: Recipe) -> DetailSheetRequest {
        DetailSheetRequest(kind: .createBatch(recipe), targetID: savedID(of: recipe))
    }

    static func addPurchase(_ ingredient: Ingredient) -> DetailSheetRequest {
        DetailSheetRequest(kind: .addPurchase(ingredient), targetID: savedID(of: ingredient))
    }

    static func editIngredient(_ ingredient: Ingredient) -> DetailSheetRequest {
        DetailSheetRequest(kind: .editIngredient(ingredient), targetID: savedID(of: ingredient))
    }

    /// The predicates `DetailSheetHost` queries to tell whether the sheet's
    /// model is still in the store, so it hears of the delete the moment it
    /// lands. A duplicate merge counts as gone too: the forms read the captured
    /// row directly, and following the surviving copy would mean rebuilding
    /// them, which loses the input anyway.
    static func recipe(id: PersistentIdentifier) -> Predicate<Recipe> {
        #Predicate { $0.persistentModelID == id }
    }

    static func ingredient(id: PersistentIdentifier) -> Predicate<Ingredient> {
        #Predicate { $0.persistentModelID == id }
    }

    /// The model's id once its context has been saved. A row inserted but not
    /// yet saved, such as an ingredient added a moment ago, carries a temporary
    /// id that changes when autosave runs; a request holding it would stop
    /// matching then, and close the sheet under the user as if the row had
    /// been deleted.
    private static func savedID(of model: some PersistentModel) -> PersistentIdentifier {
        if let context = model.modelContext, context.hasChanges {
            do {
                try context.save()
            } catch {
                log.error("Saving before opening a detail sheet failed: \(error, privacy: .public)")
            }
        }
        return model.persistentModelID
    }
}
