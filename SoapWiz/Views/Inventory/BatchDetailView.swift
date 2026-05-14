import SwiftUI

struct BatchDetailView: View {
    let batch: IngredientBatch

    @State private var model: BatchDetailViewModel
    @State private var showingEdit = false
    @FocusState private var amountFocused: Bool

    init(batch: IngredientBatch) {
        self.batch = batch
        _model = State(initialValue: BatchDetailViewModel(batch: batch))
    }

    private var unit: String { batch.ingredient?.unit?.symbol ?? "" }

    var body: some View {
        List {
            Section("Purchase") {
                LabeledContent("Provider", value: batch.provider?.name ?? "—")
                LabeledContent("Date", value: batch.dateOfPurchase.formatted(date: .long, time: .omitted))
                LabeledContent(
                    "Quantity",
                    value: "\(batch.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
                )
                LabeledContent(
                    "Total Price",
                    value: batch.totalPrice.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                )
                LabeledContent(
                    "Price / \(unit.isEmpty ? "unit" : unit)",
                    value: batch.pricePerUnit.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                )
            }

            Section("Stock") {
                HStack {
                    Text("Remaining")
                        .foregroundStyle(.primary)
                    Spacer()
                    if model.isEditingAmount {
                        HStack(spacing: 8) {
                            TextField("Amount", text: $model.editingValue)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 80)
                                .focused($amountFocused)
                                .onSubmit { model.commitEdit() }
                            Button("Done") { model.commitEdit() }
                                .font(.subheadline.bold())
                        }
                    } else {
                        HStack(spacing: 8) {
                            if model.isDirty {
                                Button { model.undo() } label: {
                                    Image(systemName: "arrow.uturn.backward.circle.fill")
                                        .font(.title2)
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.orange)
                            }

                            Button { model.adjust(by: -10) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)

                            Button { model.startEditing() } label: {
                                ZStack {
                                    Text("\(batch.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(unit)")
                                        .hidden()
                                    Text("\(batch.remainingAmount.formatted(.number.precision(.fractionLength(0...2)))) \(unit)")
                                        .foregroundStyle(batch.remainingAmount > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
                                }
                            }
                            .buttonStyle(.plain)

                            Button { model.adjust(by: 10) } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)

                        }
                    }
                }
                .onChange(of: model.isEditingAmount) {
                    if model.isEditingAmount { amountFocused = true }
                }
                LabeledContent("Storage Location", value: batch.storageLocation?.name ?? "—")
            }

            Section("Identification") {
                LabeledContent("Badge", value: batch.badge.isEmpty ? "—" : batch.badge)
                LabeledContent("Journal Code", value: batch.journalCode.isEmpty ? "—" : batch.journalCode)
            }

            Section("Dates") {
                if let expiry = batch.expiryDate {
                    LabeledContent("Expiry Date", value: expiry.formatted(date: .long, time: .omitted))
                }
                if let opening = batch.openingDate {
                    LabeledContent("Opening Date", value: opening.formatted(date: .long, time: .omitted))
                }
                if batch.expiryDate == nil && batch.openingDate == nil {
                    Text("No dates recorded")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear { model.isEditingAmount = false }
        .navigationTitle("Batch Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let ingredient = batch.ingredient {
                BatchFormView(ingredient: ingredient, batch: batch)
            }
        }
    }
}
