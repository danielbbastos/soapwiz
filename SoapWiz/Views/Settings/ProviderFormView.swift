import SwiftUI
import SwiftData

struct ProviderFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Provider.name) private var allProviders: [Provider]

    @State private var model: ProviderFormViewModel
    let onSave: ((Provider) -> Void)?

    init(provider: Provider? = nil, onSave: ((Provider) -> Void)? = nil) {
        _model = State(initialValue: ProviderFormViewModel(provider: provider))
        self.onSave = onSave
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
                .listRowBackground(Color.cardBackground)

                Section("Website") {
                    TextField("https://…", text: $model.website)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
                .listRowBackground(Color.cardBackground)

                Section("Notes") {
                    TextField("Optional (e.g. lead time, minimum order)", text: $model.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                .listRowBackground(Color.cardBackground)
            }
            .navigationTitle(model.isEditing ? "Edit Provider" : "New Provider")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle(model.isEditing ? "Edit Provider" : "New Provider")
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
                    .disabled(!model.isValid(among: allProviders))
                }
            }
        }
    }
}
