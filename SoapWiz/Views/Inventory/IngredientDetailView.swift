import SwiftUI
import SwiftData

struct IngredientDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var model: IngredientDetailViewModel

    init(ingredient: Ingredient, autoAddPurchase: Bool = false) {
        _model = State(initialValue: IngredientDetailViewModel(ingredient: ingredient, showingAddPurchase: autoAddPurchase))
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
                    LabeledContent("Purchases", value: "\(model.ingredient.purchases.count)")
                    if let sap = model.ingredient.sapValue {
                        LabeledContent("SAP Value (NaOH)") {
                            Text("\(sap.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))) g/g")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if IngredientUnitConverter.isVolume(model.ingredient.unit) {
                        LabeledContent("Density") {
                            let stored = model.ingredient.density
                            let value = stored ?? IngredientUnitConverter.defaultDensity
                            let source = stored == nil ? "default" : "custom"
                            Text("\(value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))) g/ml (\(source))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Purchases") {
                    if model.sortedPurchases.isEmpty {
                        Text("No purchases yet. Tap + to add one.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.sortedPurchases) { purchase in
                            NavigationLink(destination: PurchaseDetailView(purchase: purchase)) {
                                PurchaseRowView(purchase: purchase, unit: model.ingredient.unit)
                            }
                        }
                        .onDelete { model.delete(at: $0, context: modelContext) }
                    }
                }

                Section("Usage") {
                    if model.usageEntries.isEmpty {
                        Text("Not used in any batch yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.usageEntries) { entry in
                            UsageEntryRow(entry: entry)
                        }
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

            FloatingActionButton { model.showingAddPurchase = true }
        }
        .sheet(isPresented: $model.showingAddPurchase) {
            PurchaseFormView(ingredient: model.ingredient)
        }
        .sheet(isPresented: $model.showingEditIngredient) {
            IngredientFormView(ingredient: model.ingredient)
        }
    }
}
