import SwiftUI
import SwiftData

/// Picks the ingredient an import entry's rows go onto instead of the one the
/// matcher chose. Every ingredient is offered, hidden ones too: a row hidden to
/// keep it out of the list can still be the right place for stock, and a match
/// leaves it hidden.
///
/// When the entry started as a new ingredient, a first row goes back to
/// creating it.
struct InventoryImportMatchPickerView: View {
    let current: InventoryImportMatch?
    let canCreateNew: Bool
    var onSelect: (Ingredient) -> Void
    var onCreateNew: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var ingredients: [Ingredient]
    @State private var searchText = ""

    private var filtered: [Ingredient] {
        let sorted = ingredients.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            let rows = filtered
            VStack(spacing: 0) {
                SearchField("Search ingredients", text: $searchText)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                List {
                    if canCreateNew {
                        Section {
                            HoneyLedgerActionRow("Create as New Ingredient", systemImage: "plus") {
                                onCreateNew()
                                dismiss()
                            }
                            .ledgerSheetRow(position: .only)
                        }
                    }
                    Section {
                        ForEach(Array(rows.enumerated()), id: \.element.persistentModelID) { index, ingredient in
                            ingredientRow(ingredient, position: .position(index: index, count: rows.count))
                        }
                    }
                }
                .environment(\.defaultMinListRowHeight, 48)
                .overlay {
                    if rows.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
                .readableWidth()
            }
            .navigationTitle("Match to Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle("Match to Ingredient")
            .ledgerBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func ingredientRow(_ ingredient: Ingredient, position: LedgerSheetPosition) -> some View {
        let isSelected = current?.ingredient === ingredient
        return Button {
            onSelect(ingredient)
            dismiss()
        } label: {
            HoneyLedgerPickerRow(state: isSelected ? .selected : .unselected) {
                HStack(spacing: 8) {
                    Text(ingredient.name)
                        .foregroundStyle(Color.ink)
                    if ingredient.isHidden {
                        StatusStamp(word: "Hidden", tone: .neutral)
                    }
                }
            }
        }
        .ledgerListDetailRow(isSelected: isSelected, position: position)
    }
}
