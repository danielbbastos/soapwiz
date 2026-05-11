import SwiftUI
import SwiftData

struct QuantityUnitFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \QuantityUnit.name) private var allUnits: [QuantityUnit]

    @State private var model: QuantityUnitFormViewModel

    init(unit: QuantityUnit? = nil) {
        _model = State(initialValue: QuantityUnitFormViewModel(unit: unit))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $model.name)
                    TextField("Symbol", text: $model.symbol)
                } footer: {
                    if model.isDuplicateName(among: allUnits) {
                        Text("A unit with this name already exists.")
                            .foregroundStyle(.red)
                    } else if model.isDuplicateSymbol(among: allUnits) {
                        Text("A unit with this symbol already exists.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(model.isEditing ? "Edit Unit" : "New Unit")
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
                    .disabled(!model.isValid(among: allUnits))
                }
            }
        }
    }
}
