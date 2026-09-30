import SwiftUI
import SwiftData

/// Changes a batch's code — the one thing on a batch that can be edited after
/// the fact, for makers who number their batches their own way. Everything
/// else the batch recorded stays as it was made.
struct BatchCodeEditSheet: View {
    let batch: Batch

    @Environment(\.dismiss) private var dismiss
    @Query private var batches: [Batch]
    @State private var code: String

    init(batch: Batch) {
        self.batch = batch
        _code = State(initialValue: batch.code)
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
                    }
                    .disabled(codeIsTaken || BatchCodeGenerator.trimmed(code).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
