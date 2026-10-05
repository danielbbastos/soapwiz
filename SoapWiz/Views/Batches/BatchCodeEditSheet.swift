import SwiftUI
import SwiftData

/// Changes a batch's code, for makers who number their batches their own way.
/// Like the cure length, it can be edited after the fact; everything else the
/// batch recorded stays as it was made.
struct BatchCodeEditSheet: View {
    let batch: Batch

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var batches: [Batch]
    @State private var code: String
    private let initialCode: String

    init(batch: Batch) {
        self.batch = batch
        _code = State(initialValue: batch.code)
        initialCode = batch.code
    }

    var body: some View {
        let codeIsTaken = BatchCodeGenerator.isTaken(code, among: batches, excluding: batch)
        NavigationStack {
            Form {
                Section {
                    TextField("Batch Code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The code that goes on the label of everything made in this batch.")
                        if codeIsTaken {
                            BatchCodeDuplicateWarning()
                        }
                    }
                }
                .listRowBackground(Color.cardBackground)
            }
            .navigationTitle("Batch Code")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Batch Code")
            .warmBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        batch.code = BatchCodeGenerator.trimmed(code)
                        dismiss()
                        // The cure reminders name the batch by its code.
                        if batch.cureDays > 0 {
                            Task { await NotificationService.syncIfEnabled(modelContext: modelContext) }
                        }
                    }
                    .disabled(codeIsTaken || BatchCodeGenerator.trimmed(code).isEmpty)
                }
            }
            .interactiveDismissDisabled(code != initialCode)
        }
        .presentationDetents([.medium, .large])
    }
}
