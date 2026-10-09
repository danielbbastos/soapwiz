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
                    HoneyLedgerField(
                        "Name",
                        text: $model.name,
                        prompt: "Required",
                        error: model.isDuplicate(among: allCollections)
                            ? String(localized: "A collection with this name already exists.") : nil
                    )
                    .ledgerSheetRow(position: .only)
                }

                Section {
                    colorGrid
                        .ledgerSheetRow(position: .only)
                } header: {
                    HoneyLedgerSectionLabel("Colour")
                }
            }
            .navigationTitle(model.isEditing ? "Edit Collection" : "New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle(model.isEditing ? "Edit Collection" : "New Collection")
            .ledgerBackground()
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
            .interactiveDismissDisabled(model.isDirty)
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
