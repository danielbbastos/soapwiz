import SwiftUI
import SwiftData

/// The sheet for a `DetailSheetRequest`, presented by `ContentView` above the
/// tabs. Each form is built only while its model is still stored; once it has
/// gone the form is dropped before it can read the deleted model, and the
/// request is cleared, which closes the sheet.
struct DetailSheetHost: View {
    let request: DetailSheetRequest

    var body: some View {
        switch request.kind {
        case .createBatch(let recipe):
            StoredModelGate(filter: DetailSheetRequest.recipe(id: request.targetID), requestID: request.id) {
                CreateBatchHost(recipe: recipe)
            }
        case .addPurchase(let ingredient):
            StoredModelGate(filter: DetailSheetRequest.ingredient(id: request.targetID), requestID: request.id) {
                PurchaseFormView(ingredient: ingredient)
            }
        case .editIngredient(let ingredient):
            StoredModelGate(filter: DetailSheetRequest.ingredient(id: request.targetID), requestID: request.id) {
                IngredientFormView(ingredient: ingredient)
            }
        }
    }
}

/// Shows `content` while a row matching `filter` is in the store, and closes
/// the sheet once none is. A closure rather than a built view, so the form
/// and its view model, which read the model as they are made, are never
/// made for a deleted one.
private struct StoredModelGate<Model: PersistentModel, Content: View>: View {
    @Environment(AppNavigation.self) private var navigation
    @Query private var matches: [Model]

    let requestID: UUID
    let content: () -> Content

    init(filter: Predicate<Model>, requestID: UUID, @ViewBuilder content: @escaping () -> Content) {
        _matches = Query(filter: filter)
        self.requestID = requestID
        self.content = content
    }

    var body: some View {
        if matches.isEmpty {
            Color.clear
                .onAppear { navigation.closeDetailSheet(requestID) }
        } else {
            content()
        }
    }
}

/// The Create Batch sheet with the lye and neutraliser rows it resolves its
/// defaults against, queried here now that the recipe screen no longer
/// presents it.
private struct CreateBatchHost: View {
    let recipe: Recipe

    @Environment(AppNavigation.self) private var navigation
    @Query(filter: RecipeDetailView.lyesPredicate) private var lyeIngredients: [Ingredient]
    @Query(filter: RecipeDetailView.additivesPredicate) private var additiveIngredients: [Ingredient]
    @Query private var settingsRecords: [AppSettings]

    /// The visible lyes, plus this recipe's own, which may have been hidden
    /// since it was chosen.
    private var lyeCandidates: [Ingredient] {
        RecipeFormViewModel.lyeCandidates(
            visible: lyeIngredients,
            keeping: [recipe.lyeIngredient, recipe.kohLyeIngredient]
        )
    }

    /// The visible additives, plus this recipe's own neutraliser even if it has
    /// since been hidden.
    private var neutralizerCandidates: [Ingredient] {
        RecipeFormViewModel.neutralizerCandidates(
            visible: additiveIngredients,
            keeping: [recipe.neutralizerIngredient]
        )
    }

    var body: some View {
        CreateBatchSheet(
            recipe: recipe,
            lyeCandidates: lyeCandidates,
            neutralizerCandidates: neutralizerCandidates,
            tracksInventory: AppSettings.tracksInventory(from: settingsRecords)
        ) { batch in
            navigation.showBatch(batch)
        }
    }
}
