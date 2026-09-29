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
                    ContentUnavailableView(
                        "No Categories",
                        systemImage: "tag",
                        description: Text("Tap + to create your first category.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(categories) { category in
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
                            .onDelete { model.delete(at: $0, in: categories, context: modelContext) }
                            .listRowBackground(Color.cardBackground)
                        } footer: {
                            Text("Built-in categories can't be deleted, and only Others can be renamed.")
                        }
                    }
                }
            }
            .readableWidth()
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Categories")
            .warmBackground()

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
                .foregroundStyle(.primary)
            if category.isBuiltIn {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Built-in")
            }
            Spacer()
            Text("\(category.ingredients.count)")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }
}
