import SwiftUI
import SwiftData

struct IngredientDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let ingredient: Ingredient

    @State private var showingAddBatch = false
    @State private var showingEditIngredient = false

    private var sortedBatches: [IngredientBatch] {
        ingredient.batches.sorted { $0.dateOfPurchase > $1.dateOfPurchase }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                Section("Summary") {
                    if let categoryName = ingredient.category?.name {
                        LabeledContent("Category", value: categoryName)
                    }
                    LabeledContent("Unit", value: ingredient.unit)
                    LabeledContent("Total Remaining") {
                        Text("\(ingredient.totalRemaining.formatted(.number.precision(.fractionLength(0...2)))) \(ingredient.unit)")
                            .foregroundStyle(ingredient.totalRemaining > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
                    }
                    LabeledContent("Batches", value: "\(ingredient.batches.count)")
                }

                Section("Batches") {
                    if sortedBatches.isEmpty {
                        Text("No batches yet. Tap + to add one.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedBatches) { batch in
                            NavigationLink(destination: BatchDetailView(batch: batch)) {
                                BatchRowView(batch: batch, unit: ingredient.unit)
                            }
                        }
                        .onDelete(perform: deleteBatches)
                    }
                }
            }
            .navigationTitle(ingredient.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showingEditIngredient = true }
                }
            }

            FloatingActionButton { showingAddBatch = true }
        }
        .sheet(isPresented: $showingAddBatch) {
            BatchFormView(ingredient: ingredient)
        }
        .sheet(isPresented: $showingEditIngredient) {
            IngredientFormView(ingredient: ingredient)
        }
    }

    private func deleteBatches(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sortedBatches[index])
        }
    }
}
