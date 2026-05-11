import SwiftUI
import SwiftData

struct ProviderFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Provider.name) private var allProviders: [Provider]

    @State private var model: ProviderFormViewModel

    init(provider: Provider? = nil) {
        _model = State(initialValue: ProviderFormViewModel(provider: provider))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $model.name)
                } footer: {
                    if model.isDuplicate(among: allProviders) {
                        Text("A provider with this name already exists.")
                            .foregroundStyle(.red)
                    }
                }

                Section("Website") {
                    TextField("https://…", text: $model.website)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                Section("Notes") {
                    TextField("Optional (e.g. lead time, minimum order)", text: $model.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(model.isEditing ? "Edit Provider" : "New Provider")
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
                    .disabled(!model.isValid(among: allProviders))
                }
            }
        }
    }
}
