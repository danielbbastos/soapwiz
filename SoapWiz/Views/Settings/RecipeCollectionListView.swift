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
                    HoneyLedgerEmptyState(
                        "No Collections",
                        systemImage: "square.stack",
                        description: "Tap + to group your recipes into themes."
                    )
                } else {
                    List {
                        Section {
                            ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                                Button {
                                    model.collectionToEdit = collection
                                } label: {
                                    row(collection)
                                }
                                .ledgerSheetRow(position: .position(index: index, count: collections.count))
                            }
                            .onDelete { model.delete(at: $0, in: collections) }
                        } header: {
                            // The List's first-header inset leaves the ornament lower than
                            // centred; it clamps this negative padding to about 7pt up.
                            HoneyLedgerOrnament()
                                .padding(.top, -10)
                        }
                    }
                }
            }
            .readableWidth()
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle("Collections")
            .ledgerBackground()

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
                .foregroundStyle(Color.ink)
            Spacer()
            Text("\(collection.recipes.count)")
                .foregroundStyle(Color.inkSoft)
                .font(.subheadline)
                .monospacedDigit()
        }
    }
}
