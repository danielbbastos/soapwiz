import SwiftUI
import SwiftData

struct StorageLocationFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \StorageLocation.name) private var allLocations: [StorageLocation]

    @State private var model: StorageLocationFormViewModel
    let onSave: ((StorageLocation) -> Void)?

    init(location: StorageLocation? = nil, onSave: ((StorageLocation) -> Void)? = nil) {
        _model = State(initialValue: StorageLocationFormViewModel(location: location))
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
                        error: model.isDuplicate(among: allLocations)
                            ? String(localized: "A location with this name already exists.") : nil
                    )
                    .ledgerSheetRow(position: .first)
                    HoneyLedgerStackedField(
                        title: "Description",
                        text: $model.locationDescription,
                        prompt: "Optional (e.g. temperature-controlled)"
                    )
                    .ledgerSheetRow(position: .last)
                }
            }
            .navigationTitle(model.isEditing ? "Edit Location" : "New Location")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle(model.isEditing ? "Edit Location" : "New Location")
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
                    .disabled(!model.isValid(among: allLocations))
                }
            }
            .interactiveDismissDisabled(model.isDirty)
        }
    }
}
