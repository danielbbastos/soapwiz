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
                        ForEach(categories) { category in
                            Button {
                                model.categoryToEdit = category
                            } label: {
                                HStack {
                                    Text(category.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(category.ingredients.count)")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .onDelete { model.delete(at: $0, in: categories, context: modelContext) }
                    }
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.large)

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
            Text("\"\(category.name)\" is assigned to \(count) ingredient\(count == 1 ? "" : "s"). Remove the category from those ingredients first.")
        }
    }
}
