import SwiftUI
import SwiftData

/// What the item form is open for.
private enum ShoppingListFormTarget: Identifiable {
    case new
    case edit(ShoppingListItem)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let item): "edit-\(item.uuid.uuidString)"
        }
    }
}

/// The shopping list: what the inventory suggests buying, then what is to buy
/// and what has been bought. Pro.
struct ShoppingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currencyCode) private var currencyCode
    @AppStorage("shoppingListShareIncludesLastPurchase") private var includeLastPurchase = false

    // Queried here rather than passed in: the sheet reads the list only while it is open.
    @Query(sort: \ShoppingListItem.createdAt) private var items: [ShoppingListItem]

    let ingredients: [Ingredient]
    let purchases: [IngredientPurchase]
    let tracksInventory: Bool

    @State private var formTarget: ShoppingListFormTarget?
    @State private var isConfirmingRemoveAll = false
    @State private var toggleCount = 0

    private var model: ShoppingListViewModel {
        ShoppingListViewModel(modelContext: modelContext)
    }

    var body: some View {
        let items = items
        let suggestions = model.suggestions(
            items: items,
            ingredients: ingredients,
            purchases: purchases,
            tracksInventory: tracksInventory
        )
        let boughtDates = ShoppingListBought.dates(items: items, purchases: purchases)
        let toBuy = items.filter { !$0.isChecked && boughtDates[$0.persistentModelID] == nil }
        let checked = items.filter { $0.isChecked || boughtDates[$0.persistentModelID] != nil }
        let lastPurchases = LastPurchase.newest(in: purchases)
        let shareText = ShoppingListText.make(
            items: items,
            lastPurchases: includeLastPurchase ? lastPurchases : [:],
            boughtDates: boughtDates,
            currencyCode: currencyCode
        )
        NavigationStack {
            Group {
                if items.isEmpty && suggestions.isEmpty {
                    ScrollView {
                        HoneyLedgerEmptyState(
                            "Nothing to Buy",
                            systemImage: "cart",
                            description: "Add what you need, or let low and expiring ingredients show up here."
                        )
                        .padding(.vertical, 32)
                    }
                } else {
                    List {
                        if !suggestions.isEmpty {
                            suggestedSection(suggestions)
                        }
                        if !toBuy.isEmpty {
                            toBuySection(toBuy, lastPurchases: lastPurchases)
                        }
                        if !checked.isEmpty {
                            checkedSection(checked, lastPurchases: lastPurchases, boughtDates: boughtDates)
                        }
                    }
                    .sensoryFeedback(.selection, trigger: toggleCount)
                }
            }
            .confirmationDialog("Remove all items to buy?", isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
                Button("Remove ^[\(toBuy.count) item](inflect: true)", role: .destructive) {
                    model.removeAll(toBuy)
                }
            }
            .navigationTitle("Shopping list")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle("Shopping list")
            .ledgerBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !shareText.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: shareText, subject: Text("Shopping list")) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add item", systemImage: "plus") { formTarget = .new }
                }
            }
            // Changes save immediately, so a stray tap outside would only be an annoyance; Done closes the sheet.
            .interactiveDismissDisabled()
            .sheet(item: $formTarget) { target in
                switch target {
                case .new:
                    ShoppingListItemForm(ingredients: ingredients)
                case .edit(let item):
                    ShoppingListItemForm(item: item, ingredients: ingredients)
                }
            }
        }
        .fitsSheetToContent(fixedAtOpen: true)
    }

    private func suggestedSection(_ suggestions: [ShoppingSuggestion]) -> some View {
        Section {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                ShoppingSuggestionRow(suggestion: suggestion, onAdd: { model.add(suggestion) })
                    .ledgerSheetRow(position: .position(index: index, count: suggestions.count))
                    .swipeActions(edge: .trailing) {
                        Button("Dismiss") { model.dismiss(suggestion) }
                            .buttonStyle(.automatic)
                            .tint(Color.warning)
                    }
            }
        } header: {
            sectionHeader("Suggested", actionTitle: "Add all") { model.addAll(suggestions) }
        }
    }

    private func toBuySection(
        _ toBuy: [ShoppingListItem],
        lastPurchases: [PersistentIdentifier: LastPurchase]
    ) -> some View {
        Section {
            Toggle("Include last purchase details when sharing", isOn: $includeLastPurchase)
                .font(.subheadline)
                .foregroundStyle(Color.inkSoft)
                .tint(Color.amber)
                .disabled(!toBuy.contains { item in
                    item.ingredient.flatMap { lastPurchases[$0.persistentModelID] } != nil
                })
                .ledgerSheetRow(position: .position(index: 0, count: toBuy.count + 1))
            itemRows(toBuy, offset: 1, lastPurchases: lastPurchases, boughtDates: [:])
        } header: {
            sectionHeader("To buy", actionTitle: "Remove all") { isConfirmingRemoveAll = true }
        }
    }

    private func checkedSection(
        _ checked: [ShoppingListItem],
        lastPurchases: [PersistentIdentifier: LastPurchase],
        boughtDates: [PersistentIdentifier: Date]
    ) -> some View {
        Section {
            itemRows(checked, offset: 0, lastPurchases: lastPurchases, boughtDates: boughtDates)
        } header: {
            sectionHeader("Checked", actionTitle: "Clear checked") {
                model.clearChecked(in: checked, boughtDates: boughtDates)
            }
        }
    }

    private func itemRows(
        _ rows: [ShoppingListItem],
        offset: Int,
        lastPurchases: [PersistentIdentifier: LastPurchase],
        boughtDates: [PersistentIdentifier: Date]
    ) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
            ShoppingListItemRow(
                item: item,
                lastPurchase: item.ingredient.flatMap { lastPurchases[$0.persistentModelID] },
                boughtDate: boughtDates[item.persistentModelID],
                onToggle: {
                    toggleCount += 1
                    model.toggle(item)
                },
                onEdit: { formTarget = .edit(item) }
            )
            .ledgerSheetRow(position: .position(index: index + offset, count: rows.count + offset))
            .swipeActions(edge: .trailing) {
                Button("Remove") { model.delete(item) }
                    .buttonStyle(.automatic)
                    .tint(Color.danger)
            }
        }
    }

    private func sectionHeader(
        _ title: String,
        actionTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            HoneyLedgerSectionLabel(title)
            Button(actionTitle, action: action)
                .buttonStyle(.borderless)
                .font(.subheadline)
                .textCase(nil)
                .foregroundStyle(Color.amberText)
                .fixedSize()
        }
    }
}
