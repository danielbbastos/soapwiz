import SwiftUI
import SwiftData

struct RecipeCollectionFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \RecipeCollection.name) private var allCollections: [RecipeCollection]

    @State private var model: RecipeCollectionFormViewModel
    let onSave: ((RecipeCollection) -> Void)?

    init(collection: RecipeCollection? = nil, onSave: ((RecipeCollection) -> Void)? = nil) {
        _model = State(initialValue: RecipeCollectionFormViewModel(collection: collection))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $model.name)
                } footer: {
                    if model.isDuplicate(among: allCollections) {
                        Text("A collection with this name already exists.")
                            .foregroundStyle(.red)
                    }
                }
                .listRowBackground(Color.cardBackground)

                Section("Colour") {
                    colorGrid
                }
                .listRowBackground(Color.cardBackground)
            }
            .navigationTitle(model.isEditing ? "Edit Collection" : "New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle(model.isEditing ? "Edit Collection" : "New Collection")
            .warmBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isEditing ? "Save" : "Add") {
                        let saved = model.save(context: modelContext)
                        onSave?(saved)
                        dismiss()
                    }
                    .disabled(!model.isValid(among: allCollections))
                }
            }
        }
    }

    /// Swatches rather than a menu picker: the colour is the thing being chosen,
    /// so showing all of them at once beats hiding them behind their names.
    private var colorGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            ForEach(CollectionColor.allCases) { option in
                Button {
                    model.color = option
                } label: {
                    Circle()
                        .fill(option.tint)
                        .frame(width: 32, height: 32)
                        .overlay {
                            if model.color == option {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(model.color == option ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
