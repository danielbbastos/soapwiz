import SwiftUI
import SwiftData

/// Prompts for how many batches to make and creates one. Insufficient stock is
/// surfaced inline — the affected ingredients and shortfalls are listed and
/// creation is blocked until the count is reduced or stock is replenished.
/// With inventory tracking off there is no stock check and no cost estimate.
struct CreateBatchSheet: View {
    @Environment(\.currencyCode) private var currencyCode
    let recipe: Recipe
    let lyeCandidates: [Ingredient]
    let neutralizerCandidates: [Ingredient]
    /// Called with the created batch so the caller can navigate to it.
    let onCreated: (Batch) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var batches: [Batch]
    @State private var model: BatchProductionViewModel

    init(
        recipe: Recipe,
        lyeCandidates: [Ingredient],
        neutralizerCandidates: [Ingredient],
        tracksInventory: Bool,
        onCreated: @escaping (Batch) -> Void
    ) {
        self.recipe = recipe
        self.lyeCandidates = lyeCandidates
        self.neutralizerCandidates = neutralizerCandidates
        self.onCreated = onCreated
        _model = State(initialValue: BatchProductionViewModel(
            recipe: recipe,
            lyeCandidates: lyeCandidates,
            neutralizerCandidates: neutralizerCandidates,
            tracksInventory: tracksInventory
        ))
    }

    private func amountText(_ amount: Double, unit: String) -> String {
        "\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
    }

    var body: some View {
        let existingCodes = batches.map(\.code)
        let codeIsTaken = model.codeIsTaken(among: batches)
        NavigationStack {
            Form {
                let requirements = model.requirements
                let shortages = model.shortages(in: requirements)
                let estimatedCost = model.estimatedCost
                let totalBatchWeight = model.totalBatchWeight

                Section {
                    Stepper(value: $model.batchCount, in: 1...999) {
                        LabeledContent("Batches", value: "\(model.batchCount)")
                    }
                    // Shown even when stock is short, unlike estimated cost: the
                    // size of the batch you can't yet make is what tells you how
                    // much more to buy.
                    if totalBatchWeight > 0 {
                        LabeledContent(
                            "Total weight",
                            value: amountText(totalBatchWeight, unit: model.batchWeightUnit)
                        )
                    }
                    if shortages.isEmpty && estimatedCost > 0 {
                        LabeledContent(
                            "Estimated cost",
                            value: estimatedCost.formatted(.currency(code: currencyCode))
                        )
                    }
                }
                .listRowBackground(Color.cardBackground)

                Section {
                    TextField("Batch Code", text: $model.code, prompt: Text(model.suggestedCode))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Batch Code")
                } footer: {
                    if codeIsTaken {
                        BatchCodeDuplicateWarning()
                    }
                }
                .listRowBackground(Color.cardBackground)

                if let estimate = model.cureEstimate {
                    cureSection(estimate)
                }

                if requirements.isEmpty {
                    Section {
                        Text("This recipe has no ingredients to consume.")
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.cardBackground)
                } else if !shortages.isEmpty {
                    Section {
                        ForEach(shortages) { req in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(req.ingredient.name)
                                Text("Need \(amountText(req.required, unit: req.unit)), have \(amountText(req.available, unit: req.unit))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        // Red, unlike the orange advisory warnings elsewhere: this
                        // one blocks creation rather than merely cautioning.
                        Label("Not enough stock", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Color.cardBackground)
                }
            }
            .navigationTitle("Create Batch")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Create Batch")
            .warmBackground()
            .task(id: existingCodes) {
                model.suggestCode(existingCodes: existingCodes)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if let batch = model.create(context: context) {
                            dismiss()
                            onCreated(batch)
                            if batch.cureDays > 0 {
                                Task { await NotificationService.syncIfEnabled(modelContext: context) }
                            }
                        }
                    }
                    .disabled(!model.canCreate || codeIsTaken)
                }
            }
        }
    }

    /// Only for a solid bar: a batch of anything else never mentions a cure.
    private func cureSection(_ estimate: CureEstimate) -> some View {
        Section {
            Picker("Process", selection: $model.process) {
                ForEach(SoapProcess.allCases) { process in
                    Text(process.label).tag(process)
                }
            }
            Stepper(value: $model.cureDays, in: BatchCureLimits.days, step: 7) {
                LabeledContent("Length") {
                    CureLengthText.text(days: model.cureDays)
                }
            }
            .accessibilityValue(CureLengthText.text(days: model.cureDays))
        } header: {
            Text("Cure")
        } footer: {
            Text(estimate.band.summary)
        }
        .listRowBackground(Color.cardBackground)
    }
}
