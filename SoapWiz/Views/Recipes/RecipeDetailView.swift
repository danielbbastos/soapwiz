import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    let recipe: Recipe

    // Non-private so `RecipeDetailView+Edit` can open the full-screen form.
    @Environment(AppNavigation.self) var navigation

    @Query(filter: RecipeDetailView.lyesPredicate)
    private var lyeIngredients: [Ingredient]
    @Query(filter: RecipeDetailView.additivesPredicate)
    private var additiveIngredients: [Ingredient]

    @State private var model = RecipeFormViewModel()
    @State private var showInGrams = false
    /// Set while this screen's recipe is open in the full-screen form (iPad).
    /// Non-private so `RecipeDetailView+Edit` can set it.
    @State var isAwaitingEditClose = false

    /// Driven by the hero header: true while the photo is still behind the
    /// navigation bar, which decides whether the title is drawn for a
    /// photograph or for the app's own background.
    @State private var photoCoversNavigationBar = false

    /// Sharing state, read and written by `RecipeDetailView+Share`: the file
    /// once it has been written, and the message shown if it couldn't be.
    @State var exportFile: ExportFile?
    @State var exportErrorMessage: String?

    var body: some View {
        let batch = model.wholeBatchBreakdown
        List {
            Section {
                if !recipe.desc.isEmpty {
                    HoneyLedgerNote(recipe.desc)
                        .padding(.vertical, 4)
                        .ledgerSheetRow(position: .only)
                }
            } header: {
                HoneyLedgerOrnament()
                    // Without a photo the List's first-header inset leaves the
                    // ornament lower than centred; the List clamps this negative
                    // padding, so -10 moves it up about 7pt. With a photo,
                    // `heroPhotoHeader` reserves no gap and the inset centres it.
                    .padding(.top, heroImage == nil ? -10 : 0)
            }

            collectionsSection
            RecipeDetailIngredientSections(model: model, batch: batch, showInGrams: $showInGrams)
            RecipeDetailStatsSections(stats: RecipeStats(oilDrafts: model.oilDrafts, makesSoap: model.makesSoap))
            RecipeCostSection(model: model, batch: batch)
        }
        .readableWidth()
        // Before `ledgerBackground`, whose fill would otherwise cover the photo.
        .heroPhotoHeader(
            image: heroImage,
            aspectRatio: Self.heroAspectRatio,
            coversNavigationBar: $photoCoversNavigationBar
        )
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .honeyLedgerInlineTitle(recipe.name, overPhoto: photoCoversNavigationBar)
        .ledgerBackground()
        .safeAreaInset(edge: .bottom) {
            Button {
                navigation.detailSheetRequest = .createBatch(recipe)
            } label: {
                Label("Create Batch", systemImage: "bubbles.and.sparkles.fill")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.amberText)
            }
            .glassButtonStyleIOS26()
            .controlSize(.large)
            .padding(.bottom, 8)
        }
        .toolbar {
            shareToolbarItem
            editToolbarItem
        }
        .modifier(sharingPresentation)
        // Declared here rather than on the list views because this screen is
        // pushed from two different stacks (Recipes and History), and both
        // already route a bare `Recipe` to the detail itself.
        .navigationDestination(for: RecipeEditRoute.self) { route in
            RecipeFormView(recipe: route.recipe, onSave: { _ in reload() })
        }
        // The full-screen form (iPad) has no `onSave` back to this screen, so it
        // reloads once its own edit has closed, saved or not. A screen in a tab
        // that isn't showing when that happens (a file opened mid-edit switches
        // to Recipes) reloads anyway on reappearing, through the `.task` below.
        .onChange(of: navigation.recipeFormClosings) { reloadAfterOwnEdit() }
        .task(id: recipe.persistentModelID) {
            reload()
        }
        // The merge moves the recipe's own links onto the surviving copy, but
        // the drafts loaded from them still hold the one it deleted, and the
        // next redraw reads it — the SW-209 crash.
        .onReceive(NotificationCenter.default.publisher(for: .duplicatesMerged)) { _ in
            reloadIfRecipeStillStored()
        }
        // The stored kind, not `model.makesSoap`: the model hasn't loaded on the
        // first pass, and its default would ask on a recipe with no lye.
        .lyeSafetyAcknowledgment(isRequired: RecipeKind.resolve(recipe.recipeKind) == .soap)
        .onChange(of: lyeIngredients) {
            model.resolveDefaultLyeIngredient(from: lyeIngredients)
        }
        .onChange(of: additiveIngredients) {
            model.resolveDefaultNeutralizerIngredient(from: additiveIngredients)
        }
    }

    /// Re-reads the recipe into the display model — on first appearance and
    /// again after the edit form saves and pops. Non-private for
    /// `RecipeDetailView+Edit`.
    func reload() {
        model.load(from: recipe)
        model.resolveDefaultLyeIngredient(from: lyeIngredients)
        model.resolveDefaultNeutralizerIngredient(from: additiveIngredients)
    }

    // MARK: - Collections

    /// Read-only: filing a recipe happens in the form or from the list's
    /// long-press menu, so these are chips without a control behind them, on
    /// the paper rather than in a sheet. Hidden entirely when the recipe is
    /// unfiled, so a user who never made a collection never sees an empty row.
    @ViewBuilder
    private var collectionsSection: some View {
        let collections = recipe.collections.sortedByName
        if !collections.isEmpty {
            Section {
                FlowLayout {
                    ForEach(collections) { collection in
                        HoneyLedgerChip(title: collection.name, dot: collection.color.pigment)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .accessibilityElement(children: .combine)
            } header: {
                HoneyLedgerSectionLabel("Collections")
            }
        }
    }
}
