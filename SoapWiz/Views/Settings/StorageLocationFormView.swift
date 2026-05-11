import SwiftUI
import SwiftData

struct StorageLocationFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \StorageLocation.name) private var allLocations: [StorageLocation]

    @State private var model: StorageLocationFormViewModel

    init(location: StorageLocation? = nil) {
        _model = State(initialValue: StorageLocationFormViewModel(location: location))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $model.name)
                } footer: {
                    if model.isDuplicate(among: allLocations) {
                        Text("A location with this name already exists.")
                            .foregroundStyle(.red)
                    }
                }

                Section("Description") {
                    TextField("Optional (e.g. temperature-controlled)", text: $model.locationDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(model.isEditing ? "Edit Location" : "New Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isEditing ? "Save" : "Add") {
                        model.save(context: modelContext)
                        dismiss()
                    }
                    .disabled(!model.isValid(among: allLocations))
                }
            }
        }
    }
}
