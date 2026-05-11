import SwiftUI
import SwiftData

struct ProviderFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Provider.name) private var allProviders: [Provider]

    var provider: Provider?

    @State private var name: String
    @State private var website: String
    @State private var notes: String

    init(provider: Provider? = nil) {
        self.provider = provider
        _name = State(initialValue: provider?.name ?? "")
        _website = State(initialValue: provider?.website ?? "")
        _notes = State(initialValue: provider?.notes ?? "")
    }

    private var isEditing: Bool { provider != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedWebsite: String { website.trimmingCharacters(in: .whitespaces) }
    private var trimmedNotes: String { notes.trimmingCharacters(in: .whitespaces) }

    private var isDuplicate: Bool {
        guard !trimmedName.isEmpty else { return false }
        return allProviders.contains { $0.name.lowercased() == trimmedName.lowercased() && $0 != provider }
    }

    private var isValid: Bool { !trimmedName.isEmpty && !isDuplicate }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } footer: {
                    if isDuplicate {
                        Text("A provider with this name already exists.")
                            .foregroundStyle(.red)
                    }
                }

                Section("Website") {
                    TextField("https://…", text: $website)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                Section("Notes") {
                    TextField("Optional (e.g. lead time, minimum order)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isEditing ? "Edit Provider" : "New Provider")
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
        if let provider {
            provider.name = trimmedName
            provider.website = trimmedWebsite
            provider.notes = trimmedNotes
        } else {
            modelContext.insert(Provider(name: trimmedName, website: trimmedWebsite, notes: trimmedNotes))
        }
    }
}
