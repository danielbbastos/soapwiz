import SwiftUI
import SwiftData

/// Writes a new log entry for a batch, or changes one: when it happened, what
/// happened, and the photos taken.
struct BatchLogEntryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model: BatchLogEntryFormViewModel
    @State private var confirmingDiscard = false

    init(batch: Batch, entry: BatchLogEntry? = nil) {
        _model = State(initialValue: BatchLogEntryFormViewModel(batch: batch, entry: entry))
    }

    var body: some View {
        let title = model.isEditing ? "Edit Entry" : "New Entry"
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $model.date)
                        .foregroundStyle(Color.ink)
                        .tint(Color.amberText)
                        .ledgerSheetRow(position: .position(index: 0, count: 2))
                    HoneyLedgerStackedField(
                        title: "Notes",
                        text: $model.text,
                        prompt: "What happened — pour, unmould, cut, cure check…",
                        lineLimit: 4...12
                    )
                    .ledgerSheetRow(position: .position(index: 1, count: 2))
                } header: {
                    HoneyLedgerSectionLabel("Entry")
                }

                Section {
                    BatchLogPhotosField(model: model)
                        .ledgerSheetRow(position: .only)
                } header: {
                    HoneyLedgerSectionLabel("Photos")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle(title)
            .ledgerBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if model.hasChanges {
                            confirmingDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isEditing ? "Save" : "Add") {
                        model.save(context: modelContext)
                        dismiss()
                    }
                    .disabled(!model.canSave)
                }
            }
            // An alert rather than a confirmation dialog, as on the recipe
            // form: on iPad a dialog becomes a popover without its cancel
            // button, leaving "keep editing" to a tap outside it.
            .alert("Discard changes?", isPresented: $confirmingDiscard) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("This entry has changes that haven't been saved.")
            }
        }
        // Notes and picked photos are slow to redo, so a swipe can't throw
        // them away; Cancel asks first.
        .interactiveDismissDisabled(model.hasChanges)
    }
}
