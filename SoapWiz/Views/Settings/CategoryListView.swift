import SwiftUI
import SwiftData

struct CategoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]

    @State private var showingAddCategory = false
    @State private var categoryToEdit: IngredientCategory? = nil
    @State private var deleteBlockedCategory: IngredientCategory? = nil

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
                                categoryToEdit = category
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
                        .onDelete(perform: deleteCategories)
                    }
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.large)

            FloatingActionButton { showingAddCategory = true }
        }
        .sheet(isPresented: $showingAddCategory) {
            CategoryFormView()
        }
        .sheet(item: $categoryToEdit) { category in
            CategoryFormView(category: category)
        }
        .alert(
            "Cannot Delete Category",
            isPresented: Binding(
                get: { deleteBlockedCategory != nil },
                set: { if !$0 { deleteBlockedCategory = nil } }
            ),
            presenting: deleteBlockedCategory
        ) { _ in
            Button("OK", role: .cancel) { deleteBlockedCategory = nil }
        } message: { category in
            let count = category.ingredients.count
            Text("\"\(category.name)\" is assigned to \(count) ingredient\(count == 1 ? "" : "s"). Remove the category from those ingredients first.")
        }
    }

    private func deleteCategories(at offsets: IndexSet) {
        for index in offsets {
            let category = categories[index]
            if category.ingredients.isEmpty {
                modelContext.delete(category)
            } else {
                deleteBlockedCategory = category
            }
        }
    }
}
