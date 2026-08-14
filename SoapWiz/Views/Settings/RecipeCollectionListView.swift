import SwiftUI
import SwiftData

struct RecipeCollectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode
    @Query(sort: \RecipeCollection.name) private var collections: [RecipeCollection]

    @State private var model = RecipeCollectionListViewModel()

    private var confirmingDelete: Binding<Bool> {
        Binding(
            get: { !model.confirmingDelete.isEmpty },
            set: { if !$0 { model.confirmingDelete = [] } }
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if collections.isEmpty {
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "square.stack",
                        description: Text("Tap + to group your recipes into themes.")
                    )
                } else {
                    List {
                        ForEach(collections) { collection in
                            Button {
                                model.collectionToEdit = collection
                            } label: {
                                row(collection)
                            }
                        }
                        .onDelete { model.delete(at: $0, in: collections) }
                        .listRowBackground(Color.cardBackground)
                    }
                }
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Collections")
            .warmBackground()

            if editMode?.wrappedValue != .active {
                FloatingActionButton { model.showingAddCollection = true }
            }
        }
        .sheet(isPresented: $model.showingAddCollection) {
            RecipeCollectionFormView()
        }
        .sheet(item: $model.collectionToEdit) { collection in
            RecipeCollectionFormView(collection: collection)
        }
        .alert("Delete Collection", isPresented: confirmingDelete) {
            Button("Delete", role: .destructive) {
                model.confirmDelete(context: modelContext)
            }
            Button("Cancel", role: .cancel) { model.confirmingDelete = [] }
        } message: {
            Text(model.deleteConfirmationMessage)
        }
    }

    private func row(_ collection: RecipeCollection) -> some View {
        HStack {
            Circle()
                .fill(collection.color.tint)
                .frame(width: 12, height: 12)
            Text(collection.name)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(collection.recipes.count)")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }
}
