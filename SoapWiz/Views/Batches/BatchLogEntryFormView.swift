import SwiftUI
import SwiftData

/// Writes a new log entry for a batch, or changes one: when it happened, what
/// happened, and the photos taken.
struct BatchLogEntryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model: BatchLogEntryFormViewModel

    init(batch: Batch, entry: BatchLogEntry? = nil) {
        _model = State(initialValue: BatchLogEntryFormViewModel(batch: batch, entry: entry))
    }

    var body: some View {
        let title = model.isEditing ? "Edit Entry" : "New Entry"
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $model.date)
                }
                .listRowBackground(Color.cardBackground)

                Section("Notes") {
                    TextField(
                        "What happened — pour, unmould, cut, cure check…",
                        text: $model.text,
                        axis: .vertical
                    )
                    .lineLimit(4...12)
                }
                .listRowBackground(Color.cardBackground)

                Section("Photos") {
                    BatchLogPhotosField(model: model)
                }
                .listRowBackground(Color.cardBackground)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle(title)
            .warmBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isEditing ? "Save" : "Add") {
                        model.save(context: modelContext)
                        dismiss()
                    }
                    .disabled(!model.isValid)
                }
            }
        }
    }
}
