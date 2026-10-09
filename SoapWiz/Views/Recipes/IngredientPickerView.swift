import SwiftUI
import SwiftData

/// The copy that varies with what the picker is adding: its title, the empty
/// state's title, and the note under the rows already in the recipe.
struct IngredientPickerConfig {
    let title: String
    let emptyTitle: String
    let addedNote: String

    static let oils = IngredientPickerConfig(
        title: "Add Oils",
        emptyTitle: "No oils",
        addedNote: "Oils already in this recipe are dimmed."
    )
    static let additives = IngredientPickerConfig(
        title: "Add Additives",
        emptyTitle: "No additives",
        addedNote: "Additives already in this recipe are dimmed."
    )
    static let fragrances = IngredientPickerConfig(
        title: "Add Fragrances",
        emptyTitle: "No fragrances",
        addedNote: "Fragrances already in this recipe are dimmed."
    )
    static let ingredients = IngredientPickerConfig(
        title: "Add Ingredients",
        emptyTitle: "No ingredients",
        addedNote: "Ingredients already in this recipe are dimmed."
    )
}

struct IngredientPickerView: View {
    @Query(sort: \Ingredient.name) private var allIngredients: [Ingredient]
    @Query(sort: \IngredientCategory.name) private var allCategories: [IngredientCategory]
    @Query private var settingsRecords: [AppSettings]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let config: IngredientPickerConfig
    let addedIDs: Set<PersistentIdentifier>

    /// Roles the picker will offer. `nil` means every role. A non-soap recipe's
    /// merged Ingredients section passes both `.oil` and `.additive`, so waxes,
    /// fats, butters and additives all appear in one list.
    var allowedRoles: Set<RecipeIngredientRole>?
    /// Whether categories with no `ingredientRole` — the "Others" bucket — are
    /// also offered. A non-soap recipe's Ingredients section sets this so a
    /// general ingredient that is neither oil, additive nor fragrance can still
    /// be chosen; soap pickers leave it off.
    var includesUnroled = false
    let onSelect: ([Ingredient]) -> Void

    @State private var searchText = ""
    @State private var selectedCategory: IngredientCategory?
    @State private var showsInStockOnly = false
    @State private var pendingSelections = PendingIngredientSelection()
    @State private var showingNewIngredient = false

    /// Whether an ingredient or category with the given role is offered by a
    /// picker configured with these options. A `nil` role is the "Others"
    /// bucket; a `nil` `allowedRoles` offers every role.
    static func accepts(role: RecipeIngredientRole?, allowedRoles: Set<RecipeIngredientRole>?, includesUnroled: Bool) -> Bool {
        guard let allowedRoles else { return true }
        guard let role else { return includesUnroled }
        return allowedRoles.contains(role)
    }

    private var tracksInventory: Bool { AppSettings.tracksInventory(from: settingsRecords) }

    private var categories: [IngredientCategory] {
        allCategories.filter { category in
            Self.accepts(role: category.ingredientRole, allowedRoles: allowedRoles, includesUnroled: includesUnroled)
        }
    }

    /// Category to pre-select when creating a new ingredient inline: the chosen
    /// chip if any, otherwise the first category matching the picker's role.
    private var defaultCategory: IngredientCategory? {
        selectedCategory ?? categories.first
    }

    private var filtered: [Ingredient] {
        IngredientPickerFilter(
            searchText: searchText,
            category: selectedCategory,
            inStockOnly: showsInStockOnly && tracksInventory
        )
        .choices(from: allIngredients, allowedRoles: allowedRoles, includesUnroled: includesUnroled)
    }

    /// The gap between the two sheets, matching the one from the chip capsule to
    /// the first sheet: the chip row's 12pt bottom padding plus the 4pt
    /// `FilterChip` draws around its ledger capsule.
    private static let sheetSpacing: CGFloat = 16

    /// The title of the confirm button: how many ticked rows it will add.
    static func confirmTitle(count: Int) -> String {
        count > 0 ? String(localized: "Add \(count)") : String(localized: "Add")
    }

    var body: some View {
        NavigationStack {
            let rows = filtered
            VStack(spacing: 0) {
                SearchField("Search ingredients", text: $searchText)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                if !categories.isEmpty {
                    chipRow
                }
                List {
                    Section {
                        Button {
                            showingNewIngredient = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                Text("Add new ingredient")
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.amberText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .ledgerSheetRow(position: .only)
                    }
                    if rows.isEmpty {
                        Section {
                            emptyState
                                .frame(height: 280)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } else {
                        Section {
                            ForEach(Array(rows.enumerated()), id: \.element.persistentModelID) { index, ingredient in
                                ingredientRow(ingredient, position: .position(index: index, count: rows.count))
                            }
                        } footer: {
                            if rows.contains(where: { addedIDs.contains($0.persistentModelID) }) {
                                Text(config.addedNote)
                                    .font(.footnote)
                                    .foregroundStyle(Color.inkSoft)
                            }
                        }
                    }
                }
                .environment(\.defaultMinListRowHeight, 48)
                // The chips already stand off the list on their own; the
                // scroll view's default top margin on top of that left the
                // two looking unrelated.
                .contentMargins(.top, categories.isEmpty ? nil : 0, for: .scrollContent)
                .listSectionSpacing(Self.sheetSpacing)
                .readableWidth()
            }
            .navigationTitle(config.title)
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle(config.title)
            .ledgerBackground()
            // Every device installs its own categories, so the first sync on a
            // joining device merges the chip's copy away. Kept, it would empty
            // the list and reach "Add new ingredient" as a row that traps when
            // read. Its name is gone with it, so the chip falls back to All.
            .onReceive(NotificationCenter.default.publisher(for: .duplicatesMerged)) { _ in
                if selectedCategory?.modelContext == nil {
                    selectedCategory = nil
                }
                pendingSelections.followMerge(in: modelContext)
            }
            .sheet(isPresented: $showingNewIngredient) {
                IngredientFormView(defaultCategory: defaultCategory) { newIngredient in
                    pendingSelections.insert(newIngredient)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Self.confirmTitle(count: pendingSelections.count)) {
                        let selected = allIngredients.filter { pendingSelections.contains($0.persistentModelID) }
                        onSelect(selected)
                        dismiss()
                    }
                    .disabled(pendingSelections.isEmpty)
                }
            }
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip("All", isSelected: selectedCategory == nil, style: .ledger) {
                    selectedCategory = nil
                }
                if tracksInventory {
                    FilterChip("In stock", isSelected: showsInStockOnly, style: .ledger) {
                        showsInStockOnly.toggle()
                    }
                }
                ForEach(categories) { category in
                    FilterChip(
                        category.name,
                        isSelected: selectedCategory?.persistentModelID == category.persistentModelID,
                        style: .ledger
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        // Less the chips' own padding, so the first chip lines up with the
        // capped list below it.
        .readableWidth(inset: 16)
    }

    /// Drawn in place of the ingredient sheet, so "Add new ingredient" above it
    /// stays reachable.
    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            HoneyLedgerEmptyState(
                LocalizedStringKey(config.emptyTitle),
                systemImage: "tray",
                description: "Add one, or change the filters."
            )
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private func ingredientRow(_ ingredient: Ingredient, position: LedgerSheetPosition) -> some View {
        let isAdded = addedIDs.contains(ingredient.persistentModelID)
        let isPending = pendingSelections.contains(ingredient.persistentModelID)
        let state: HoneyLedgerPickerRowState = isAdded ? .added : (isPending ? .selected : .unselected)
        return Button {
            pendingSelections.toggle(ingredient)
        } label: {
            HoneyLedgerPickerRow(name: ingredient.name, state: state)
        }
        .disabled(isAdded)
        .ledgerListDetailRow(isSelected: state == .selected, position: position)
    }
}
