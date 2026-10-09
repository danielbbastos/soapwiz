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
                    HoneyLedgerField(
                        "Name",
                        text: $model.name,
                        prompt: "Required",
                        error: model.isDuplicate(among: allProviders)
                            ? String(localized: "A provider with this name already exists.") : nil
                    )
                    .ledgerSheetRow(position: .first)
                    HoneyLedgerField("Website") { focus in
                        TextField("Website", text: $model.website, prompt: Text("https://…").foregroundStyle(Color.inkFaint))
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .focused(focus)
                    }
                    .ledgerSheetRow(position: .middle)
                    HoneyLedgerStackedField(
                        title: "Notes",
                        text: $model.notes,
                        prompt: "Optional (e.g. lead time, minimum order)"
                    )
                    .ledgerSheetRow(position: .last)
                }
            }
            .navigationTitle(model.isEditing ? "Edit Provider" : "New Provider")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle(model.isEditing ? "Edit Provider" : "New Provider")
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
                    .disabled(!model.isValid(among: allProviders))
                }
            }
            .interactiveDismissDisabled(model.isDirty)
        }
    }
}
