import SwiftUI
import SwiftData

struct BatchFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let ingredient: Ingredient
    var batch: IngredientBatch? = nil

    @State private var provider = ""
    @State private var dateOfPurchase = Date()
    @State private var quantityText = ""
    @State private var totalPriceText = ""
    @State private var badge = ""
    @State private var journalCode = ""
    @State private var hasExpiryDate = false
    @State private var expiryDate = Date()
    @State private var hasOpeningDate = false
    @State private var openingDate = Date()
    @State private var storageLocation = ""

    private var isEditing: Bool { batch != nil }
    private var quantity: Double { Double(quantityText) ?? 0 }
    private var totalPrice: Double { Double(totalPriceText) ?? 0 }
    private var pricePerUnit: Double {
        guard quantity > 0 else { return 0 }
        return totalPrice / quantity
    }
    private var isValid: Bool { quantity > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Purchase") {
                    TextField("Provider", text: $provider)
                    DatePicker("Date of Purchase", selection: $dateOfPurchase, displayedComponents: .date)
                    HStack {
                        Text("Quantity (\(ingredient.unit))")
                        Spacer()
                        TextField("0", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Total Price")
                        Spacer()
                        TextField("0.00", text: $totalPriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    if quantity > 0 && totalPrice > 0 {
                        LabeledContent("Price / \(ingredient.unit)") {
                            Text(pricePerUnit.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Identification") {
                    TextField("Badge / Lot Number", text: $badge)
                    TextField("Journal Code", text: $journalCode)
                }

                Section("Dates") {
                    Toggle("Has Expiry Date", isOn: $hasExpiryDate)
                    if hasExpiryDate {
                        DatePicker("Expiry Date", selection: $expiryDate, displayedComponents: .date)
                    }
                    Toggle("Has Opening Date", isOn: $hasOpeningDate)
                    if hasOpeningDate {
                        DatePicker("Opening Date", selection: $openingDate, displayedComponents: .date)
                    }
                }

                Section("Storage") {
                    TextField("Storage Location", text: $storageLocation)
                }
            }
            .navigationTitle(isEditing ? "Edit Batch" : "New Batch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .onAppear {
            guard let batch else { return }
            provider = batch.provider
            dateOfPurchase = batch.dateOfPurchase
            quantityText = batch.quantity.formatted(.number.precision(.fractionLength(0...2)))
            totalPriceText = batch.totalPrice.formatted(.number.precision(.fractionLength(0...2)))
            badge = batch.badge
            journalCode = batch.journalCode
            if let expiry = batch.expiryDate {
                hasExpiryDate = true
                expiryDate = expiry
            }
            if let opening = batch.openingDate {
                hasOpeningDate = true
                openingDate = opening
            }
            storageLocation = batch.storageLocation
        }
    }

    private func save() {
        if let batch {
            batch.provider = provider
            batch.dateOfPurchase = dateOfPurchase
            batch.quantity = quantity
            batch.totalPrice = totalPrice
            batch.badge = badge
            batch.journalCode = journalCode
            batch.expiryDate = hasExpiryDate ? expiryDate : nil
            batch.openingDate = hasOpeningDate ? openingDate : nil
            batch.storageLocation = storageLocation
        } else {
            let newBatch = IngredientBatch(
                provider: provider,
                dateOfPurchase: dateOfPurchase,
                quantity: quantity,
                totalPrice: totalPrice,
                badge: badge,
                journalCode: journalCode,
                expiryDate: hasExpiryDate ? expiryDate : nil,
                openingDate: hasOpeningDate ? openingDate : nil,
                storageLocation: storageLocation
            )
            modelContext.insert(newBatch)
            ingredient.batches.append(newBatch)
        }
    }
}
