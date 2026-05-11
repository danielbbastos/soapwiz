import SwiftUI
import SwiftData

struct StorageLocationFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \StorageLocation.name) private var allLocations: [StorageLocation]

    var location: StorageLocation?

    @State private var name: String
    @State private var locationDescription: String

    init(location: StorageLocation? = nil) {
        self.location = location
        _name = State(initialValue: location?.name ?? "")
        _locationDescription = State(initialValue: location?.locationDescription ?? "")
    }

    private var isEditing: Bool { location != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedDescription: String { locationDescription.trimmingCharacters(in: .whitespaces) }

    private var isDuplicate: Bool {
        guard !trimmedName.isEmpty else { return false }
        return allLocations.contains { $0.name.lowercased() == trimmedName.lowercased() && $0 != location }
    }

    private var isValid: Bool { !trimmedName.isEmpty && !isDuplicate }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } footer: {
                    if isDuplicate {
                        Text("A location with this name already exists.")
                            .foregroundStyle(.red)
                    }
                }

                Section("Description") {
                    TextField("Optional (e.g. temperature-controlled)", text: $locationDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isEditing ? "Edit Location" : "New Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        if let location {
            location.name = trimmedName
            location.locationDescription = trimmedDescription
        } else {
            modelContext.insert(StorageLocation(name: trimmedName, locationDescription: trimmedDescription))
        }
    }
}
