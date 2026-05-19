import SwiftUI
import SwiftData

struct IngredientDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var model: IngredientDetailViewModel

    init(ingredient: Ingredient, autoAddBatch: Bool = false) {
        _model = State(initialValue: IngredientDetailViewModel(ingredient: ingredient, showingAddBatch: autoAddBatch))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                Section("Summary") {
                    if let categoryName = model.ingredient.category?.name {
                        LabeledContent("Category", value: categoryName)
                    }
                    if !model.ingredient.unit.isEmpty {
                        LabeledContent("Unit", value: IngredientUnit(rawValue: model.ingredient.unit)?.label ?? model.ingredient.unit)
                    }
                    LabeledContent("Total Remaining") {
                        let symbol = model.ingredient.unit
                        Text("\(model.totalRemaining.formatted(.number.precision(.fractionLength(0...2)))) \(symbol)")
                            .foregroundStyle(model.totalRemaining > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
                    }
                    LabeledContent("Batches", value: "\(model.ingredient.batches.count)")
                    if let sap = model.ingredient.sapValue {
                        LabeledContent("SAP Value (NaOH)") {
                            Text("\(sap.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))) g/g")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let dens = model.ingredient.density {
                        LabeledContent("Density") {
                            Text("\(dens.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))) g/ml")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Batches") {
                    if model.sortedBatches.isEmpty {
                        Text("No batches yet. Tap + to add one.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.sortedBatches) { batch in
                            NavigationLink(destination: BatchDetailView(batch: batch)) {
                                BatchRowView(batch: batch, unit: model.ingredient.unit)
                            }
                        }
                        .onDelete { model.delete(at: $0, context: modelContext) }
                    }
                }
            }
            .navigationTitle(model.ingredient.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { model.showingEditIngredient = true }
                }
            }

            FloatingActionButton { model.showingAddBatch = true }
        }
        .sheet(isPresented: $model.showingAddBatch) {
            BatchFormView(ingredient: model.ingredient)
        }
        .sheet(isPresented: $model.showingEditIngredient) {
            IngredientFormView(ingredient: model.ingredient)
        }
    }
}
