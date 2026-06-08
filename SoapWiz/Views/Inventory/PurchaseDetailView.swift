import SwiftUI

struct PurchaseDetailView: View {
    let purchase: IngredientPurchase

    @State private var model: PurchaseDetailViewModel
    @State private var showingEdit = false
    @FocusState private var amountFocused: Bool

    init(purchase: IngredientPurchase) {
        self.purchase = purchase
        _model = State(initialValue: PurchaseDetailViewModel(purchase: purchase))
    }

    private var unit: String { purchase.ingredient?.unit ?? "" }

    var body: some View {
        List {
            Section("Purchase") {
                LabeledContent("Provider", value: purchase.provider?.name ?? "—")
                LabeledContent("Date", value: purchase.dateOfPurchase.formatted(date: .long, time: .omitted))
                LabeledContent(
                    "Quantity",
                    value: "\(purchase.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
                )
                LabeledContent(
                    "Total Price",
                    value: purchase.totalPrice.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                )
                LabeledContent(
                    "Price / \(unit.isEmpty ? "unit" : unit)",
                    value: purchase.pricePerUnit.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                )
            }

            Section("Stock") {
                HStack {
                    Text("Remaining")
                        .foregroundStyle(.primary)
                    Spacer()
                    if model.isEditingAmount {
                        HStack(spacing: 8) {
                            TextField("Amount", text: $model.editingValue.decimalOnly())
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
                                    Text("\(purchase.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(unit)")
                                        .hidden()
                                    Text("\(purchase.remainingAmount.formatted(.number.precision(.fractionLength(0...2)))) \(unit)")
                                        .foregroundStyle(purchase.remainingAmount > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
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
                LabeledContent("Storage Location", value: purchase.storageLocation?.name ?? "—")
            }

            Section("Identification") {
                LabeledContent("Badge", value: purchase.badge.isEmpty ? "—" : purchase.badge)
                LabeledContent("Journal Code", value: purchase.journalCode.isEmpty ? "—" : purchase.journalCode)
            }

            Section("Dates") {
                if let expiry = purchase.expiryDate {
                    LabeledContent("Expiry Date", value: expiry.formatted(date: .long, time: .omitted))
                }
                if let opening = purchase.openingDate {
                    LabeledContent("Opening Date", value: opening.formatted(date: .long, time: .omitted))
                }
                if purchase.expiryDate == nil && purchase.openingDate == nil {
                    Text("No dates recorded")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear { model.isEditingAmount = false }
        .navigationTitle("Purchase Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let ingredient = purchase.ingredient {
                PurchaseFormView(ingredient: ingredient, purchase: purchase)
            }
        }
    }
}
