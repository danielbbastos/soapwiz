import SwiftUI
import SwiftData

private enum RecipeTab: String, CaseIterable {
    case config = "Config"
    case ingredients = "Ingredients"
    case stats = "Stats"
}

struct RecipeFormView: View {
    private static let lyesPredicate: Predicate<Ingredient> = {
        let name = IngredientCategory.Name.lyes
        return #Predicate { $0.category?.name == name }
    }()

    var recipe: Recipe?
    var seed: RecipeSeed?
    var importDraft: PreparedRecipeImport?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: lyesPredicate)
    private var lyeIngredients: [Ingredient]

    @State private var model = RecipeFormViewModel()
    @State private var selectedTab: RecipeTab = .config
    @State private var showDiscardConfirmation = false

    var onSave: ((Recipe) -> Void)?

    var body: some View {
        currentTab
            .scrollContentBackground(.hidden)
            .background(Color.warmBackground.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                tabPicker
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .task(id: recipe?.persistentModelID) {
                if let recipe { model.load(from: recipe) }
                // The baseline is taken before any seed or import so a pre-filled
                // new recipe counts as unsaved work, but after loading an
                // existing one so opening it to look doesn't.
                model.captureSnapshot()
                if let seed { model.applySeed(seed.ingredients) }
                if let importDraft { model.applyImport(importDraft) }
                model.resolveDefaultLyeIngredient(from: lyeIngredients)
            }
            .onChange(of: lyeIngredients) {
                model.resolveDefaultLyeIngredient(from: lyeIngredients)
            }
            // Cancel is the only way out, so a swipe can't discard the form by
            // accident — the feedback behind SW-106.
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { attemptDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let recipe = model.save(context: modelContext)
                        onSave?(recipe)
                        dismiss()
                    }
                    .disabled(!model.canSave)
                }
            }
            // An alert rather than a confirmation dialog: on iPad the latter
            // renders as a popover that drops the cancel button entirely,
            // leaving "keep editing" to an undiscoverable tap outside.
            .alert("Discard changes?", isPresented: $showDiscardConfirmation) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("This recipe has changes that haven't been saved.")
            }
    }

    private func attemptDismiss() {
        if model.isDirty {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    @ViewBuilder
    private var currentTab: some View {
        switch selectedTab {
        case .config: configTab
        case .ingredients: ingredientsTab
        case .stats: statsTab
        }
    }

    /// The segmented control gets an opaque fill shaped to the control itself,
    /// so scrolled content never shows through the pill while the header band
    /// around it keeps the system's scroll-under glass effect.
    @ViewBuilder
    private var tabPicker: some View {
        let picker = Picker("Tab", selection: $selectedTab) {
            ForEach(RecipeTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)

        if #available(iOS 26, *) {
            picker.background(Color.warmBackground, in: .capsule)
        } else {
            picker.background(Color.warmBackground, in: .rect(cornerRadius: 8))
        }
    }
}

// MARK: - Tabs

private extension RecipeFormView {
    var configTab: some View {
        RecipeConfigTabView(model: model)
    }

    var ingredientsTab: some View {
        RecipeIngredientsTabView(model: model)
    }

    var statsTab: some View {
        RecipeStatsTabView(model: model)
    }
}
