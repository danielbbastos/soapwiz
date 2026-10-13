import SwiftUI
import SwiftData

struct RecipeFormView: View {
    /// Hidden lyes are excluded so the default never resolves to one the user has
    /// said they don't use. Safe because resolving only ever fills a blank — it
    /// cannot unset a lye a recipe already has.
    private static let lyesPredicate: Predicate<Ingredient> = {
        let name = IngredientCategory.Name.lyes
        return #Predicate { $0.category?.name == name && !$0.isHidden }
    }()

    /// Additives the Failor neutraliser default can resolve against. Hidden rows
    /// are excluded for the same reason the lyes are.
    private static let additivesPredicate: Predicate<Ingredient> = {
        let name = IngredientCategory.Name.additives
        return #Predicate { $0.category?.name == name && !$0.isHidden }
    }()

    var recipe: Recipe?
    var seed: RecipeSeed?
    var importDraft: PreparedRecipeImport?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: lyesPredicate)
    private var lyeIngredients: [Ingredient]
    @Query(filter: additivesPredicate)
    private var additiveIngredients: [Ingredient]

    @State private var model = RecipeFormViewModel()
    @State private var selectedTab: RecipeTab = .config
    @State private var closeReason: RecipeFormCloseReason?
    @State private var isWide = false
    /// How far the cost panel has been dragged past its default height. Kept
    /// here because the ingredients tab is rebuilt on every tab switch.
    @State private var costPanelExtraHeight: CGFloat = 0
    /// Set once the recipe, seed or import has been applied. Before that the
    /// model holds its defaults, which say soap, and would ask on a recipe
    /// with no lye.
    @State private var hasLoaded = false

    var onSave: ((Recipe) -> Void)?
    /// A recipe file waiting to open while the form covers the screen (iPad).
    /// The form offers to close for it, the way Cancel does, and again for each
    /// later open: the same file opened twice arrives at the same URL, so the
    /// request's own identity is what marks a new one.
    var incomingFile: RecipeFileImport?

    var body: some View {
        currentTab
            .environment(\.defaultMinListRowHeight, 48)
            .ledgerBackground()
            .onGeometryChange(for: Bool.self) {
                RecipeFormLayout.isWide(width: $0.size.width)
            } action: { newValue in
                isWide = newValue
                selectedTab = selectedTab.adapted(isWide: newValue)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                tabPicker
                    .shadow(color: Color.shadow.opacity(0.12), radius: 4, y: 1)
                    // Readable width in every layout; the wide columns below are wider.
                    .frame(maxWidth: ReadableWidth.maximum)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .task(id: recipe?.persistentModelID) {
                // Runs again when the form reappears after a pushed picker (lye,
                // neutraliser) is popped, not only on first appearance. Loading a
                // second time would overwrite every unsaved edit with the stored
                // recipe, so the whole setup is done exactly once.
                guard !hasLoaded else { return }
                if let recipe { model.load(from: recipe) }
                // The baseline is taken before any seed or import so a pre-filled
                // new recipe counts as unsaved work, but after loading an
                // existing one so opening it to look doesn't.
                model.captureSnapshot()
                if let seed { model.applySeed(seed.ingredients) }
                if let importDraft { model.applyImport(importDraft) }
                model.resolveDefaultLyeIngredient(from: lyeIngredients)
                model.resolveDefaultNeutralizerIngredient(from: additiveIngredients)
                hasLoaded = true
            }
            .lyeSafetyAcknowledgment(isRequired: hasLoaded && model.makesSoap)
            .onChange(of: lyeIngredients) {
                model.resolveDefaultLyeIngredient(from: lyeIngredients)
            }
            .onChange(of: additiveIngredients) {
                model.resolveDefaultNeutralizerIngredient(from: additiveIngredients)
            }
            // Resolved in place rather than reloaded, which would discard every
            // unsaved edit.
            .onReceive(NotificationCenter.default.publisher(for: .duplicatesMerged)) { _ in
                model.resolveMergedRows(in: modelContext)
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
            .alert(
                closeReason?.title ?? "",
                isPresented: Binding(get: { closeReason != nil }, set: { if !$0 { closeReason = nil } }),
                presenting: closeReason
            ) { reason in
                Button(reason.discardTitle, role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: { reason in
                Text(reason.message)
            }
            .onChange(of: incomingFile) { _, file in
                guard let file else { return }
                attemptDismiss(for: .fileImport(file.url))
            }
    }

    private func attemptDismiss(for reason: RecipeFormCloseReason = .cancel) {
        if model.isDirty {
            closeReason = reason
        } else {
            dismiss()
        }
    }

    @ViewBuilder
    private var currentTab: some View {
        switch selectedTab {
        case .config: configTab
        // Both share one branch and one view structure, so the Ingredients
        // view keeps its identity and state when the layout changes.
        case .ingredients, .ingredientsAndStats: ingredientsColumns
        case .stats: statsTab
        }
    }

    /// The system segmented control, so the tabs keep Liquid Glass on iOS 26;
    /// the paper `HoneyLedgerSegmented` is for choices inside a sheet. Its
    /// track matches that one's: an opaque `paperSunken` fill with a
    /// `ruleStrong` hairline, shaped to the control, which also keeps scrolled
    /// content from showing through. The segments' colours come from
    /// `HoneyLedgerSegmentedAppearance`.
    @ViewBuilder
    private var tabPicker: some View {
        // Before the picker's control is made, which happens after `body`.
        let _: Void = HoneyLedgerSegmentedAppearance.applied
        let picker = Picker("Tab", selection: $selectedTab) {
            ForEach(RecipeTab.tabs(isWide: isWide), id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)

        if #available(iOS 26, *) {
            picker
                .background(Color.paperSunken, in: .capsule)
                .overlay(Capsule().strokeBorder(Color.ruleStrong, lineWidth: 1))
        } else {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            picker
                .background(Color.paperSunken, in: shape)
                .overlay(shape.strokeBorder(Color.ruleStrong, lineWidth: 1))
        }
    }
}

// MARK: - Tabs

private extension RecipeFormView {
    var configTab: some View {
        RecipeConfigTabView(model: model)
    }

    var ingredientsTab: some View {
        RecipeIngredientsTabView(model: model, costPanelExtraHeight: $costPanelExtraHeight)
    }

    var statsTab: some View {
        RecipeStatsTabView(model: model)
    }

    /// Each column is its own `Form`, so each scrolls on its own. The outer
    /// full-width frame keeps the paper background filling the screen behind
    /// the capped columns.
    var ingredientsColumns: some View {
        HStack(spacing: 0) {
            ingredientsTab
            if isWide {
                Color.clear
                    .frame(width: RecipeFormLayout.columnSpacing)
                    .overlay { Rectangle().fill(Color.rule).frame(width: 1) }
                statsTab
                    .frame(width: RecipeFormLayout.statsColumnWidth)
            }
        }
        .frame(maxWidth: isWide ? RecipeFormLayout.maximumWideWidth : .infinity)
        .frame(maxWidth: .infinity)
    }
}
