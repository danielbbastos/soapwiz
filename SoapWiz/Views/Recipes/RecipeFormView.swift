import SwiftUI
import SwiftData

struct RecipeFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \QuantityUnit.name) private var quantityUnits: [QuantityUnit]

    @State private var model = RecipeFormViewModel()
    @State private var showingPicker = false
    var onSave: ((Recipe) -> Void)?

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $model.name)
                TextField("Description", text: $model.desc, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section("Ingredients") {
                HStack {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add ingredient", systemImage: "plus")
                    }
                    Spacer()
                    if !model.ingredientDrafts.isEmpty {
                        Text(model.totalPercentageText)
                            .foregroundStyle(abs(model.totalPercentage - 100) < 0.1 ? Color.green : Color.red)
                            .frame(width: 60, alignment: .trailing)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(model.ingredientDrafts) { draft in
                    HStack {
                        Text(draft.ingredient.name)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { draft.percentage },
                            set: { model.userEdited(id: draft.id, percentage: $0) }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { model.removeIngredient(at: $0) }
            }

            if !model.ingredientDrafts.isEmpty {
                Section("Products") {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 0) {
                                ForEach($model.productDrafts) { $draft in
                                    let result = model.breakdownAndCost(for: draft)
                                    RecipeProductCardView(
                                        draft: $draft,
                                        breakdown: result.breakdown,
                                        totalCost: result.total,
                                        availableUnits: quantityUnits
                                    )
                                    .containerRelativeFrame(.horizontal)
                                    .id(draft.id)
                                }
                                AddProductCardView {
                                    let symbol = quantityUnits.first?.symbol ?? ""
                                    model.addProduct(defaultUnitSymbol: symbol)
                                    if let newID = model.productDrafts.last?.id {
                                        withAnimation { proxy.scrollTo(newID) }
                                    }
                                }
                                .containerRelativeFrame(.horizontal)
                                .id("addButton")
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                    }
                    .listRowInsets(EdgeInsets())

                    if model.productDrafts.count > 0 {
                        HStack(spacing: 6) {
                            ForEach(0..<model.productDrafts.count + 1, id: \.self) { _ in
                                Circle()
                                    .fill(Color.secondary.opacity(0.5))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("New Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let recipe = model.save(context: modelContext)
                    onSave?(recipe)
                    dismiss()
                }
                .disabled(!model.canSave)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $showingPicker) {
            IngredientPickerView(
                addedIDs: Set(model.ingredientDrafts.map(\.ingredient.persistentModelID)),
                onSelect: model.addIngredient
            )
        }
    }
}
