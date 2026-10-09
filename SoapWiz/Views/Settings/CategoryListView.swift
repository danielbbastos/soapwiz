import SwiftUI
import SwiftData

struct CategoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode
    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]

    @State private var model = CategoryListViewModel()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if categories.isEmpty {
                    HoneyLedgerEmptyState(
                        "No Categories",
                        systemImage: "tag",
                        description: "Tap + to create your first category."
                    )
                } else {
                    List {
                        Section {
                            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                                Group {
                                    if category.isRenamable {
                                        Button {
                                            model.categoryToEdit = category
                                        } label: {
                                            row(for: category)
                                        }
                                        .deleteDisabled(category.isBuiltIn)
                                    } else {
                                        row(for: category)
                                            .deleteDisabled(true)
                                    }
                                }
                                .ledgerSheetRow(position: .position(index: index, count: categories.count))
                            }
                            .onDelete { model.delete(at: $0, in: categories, context: modelContext) }
                        } header: {
                            // The List's first-header inset leaves the ornament lower than
                            // centred; it clamps this negative padding to about 7pt up.
                            HoneyLedgerOrnament()
                                .padding(.top, -10)
                        } footer: {
                            HoneyLedgerFooter("Built-in categories can't be deleted, and only Others can be renamed.")
                        }
                    }
                }
            }
            .readableWidth()
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle("Categories")
            .ledgerBackground()

            if editMode?.wrappedValue != .active {
                FloatingActionButton { model.showingAddCategory = true }
            }
        }
        .sheet(isPresented: $model.showingAddCategory) {
            CategoryFormView()
        }
        .sheet(item: $model.categoryToEdit) { category in
            CategoryFormView(category: category)
        }
        .alert(
            "Cannot Delete Category",
            isPresented: Binding(
                get: { model.deleteBlockedCategory != nil },
                set: { if !$0 { model.deleteBlockedCategory = nil } }
            ),
            presenting: model.deleteBlockedCategory
        ) { _ in
            Button("OK", role: .cancel) { model.deleteBlockedCategory = nil }
        } message: { category in
            let count = category.ingredients.count
            Text("\"\(category.name)\" is assigned to \(count) ingredient\(count == 1 ? "" : "s"). "
                 + "Remove the category from those ingredients first.")
        }
    }

    private func row(for category: IngredientCategory) -> some View {
        HStack {
            Text(category.name)
                .foregroundStyle(Color.ink)
            if category.isBuiltIn {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Color.inkFaint)
                    .accessibilityLabel("Built-in")
            }
            Spacer()
            Text("\(category.ingredients.count)")
                .foregroundStyle(Color.inkSoft)
                .font(.subheadline)
                .monospacedDigit()
        }
    }
}
