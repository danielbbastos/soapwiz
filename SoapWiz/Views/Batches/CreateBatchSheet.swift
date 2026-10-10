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

    private func numberText(_ amount: Double) -> String {
        amount.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func amountText(_ amount: Double, unit: String) -> String {
        "\(numberText(amount)) \(unit)"
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

                let showsWeight = totalBatchWeight > 0
                let showsCost = shortages.isEmpty && estimatedCost > 0
                let summaryCount = 1 + (showsWeight ? 1 : 0) + (showsCost ? 1 : 0)

                Section {
                    sheetRow(0, of: summaryCount) {
                        Stepper(value: $model.batchCount, in: 1...999) {
                            HoneyLedgerStepperLabel(
                                title: "Batches",
                                value: Text("\(model.batchCount)").fontWeight(.semibold),
                                valueColor: .ink
                            )
                        }
                        .accessibilityValue("\(model.batchCount)")
                    }
                    // Shown even when stock is short, unlike estimated cost: the
                    // size of the batch you can't yet make is what tells you how
                    // much more to buy.
                    if showsWeight {
                        sheetRow(1, of: summaryCount) {
                            HoneyLedgerLabeledRow("Total weight") {
                                Text.honeyLedgerFigure(
                                    numberText(totalBatchWeight),
                                    unit: model.batchWeightUnit
                                )
                            }
                        }
                    }
                    if showsCost {
                        sheetRow(summaryCount - 1, of: summaryCount) {
                            HoneyLedgerLabeledRow("Estimated cost") {
                                Text.honeyLedgerFigure(estimatedCost.formatted(.currency(code: currencyCode)))
                            }
                        }
                    }
                } header: {
                    HoneyLedgerSectionLabel("Batch")
                }

                // Straight under the batch count: it is the lever that causes the
                // shortage and the one that fixes it.
                if requirements.isEmpty {
                    Section {
                        sheetRow(0, of: 1) {
                            Text("This recipe has no ingredients to consume.")
                                .foregroundStyle(Color.inkSoft)
                        }
                    }
                } else if !shortages.isEmpty {
                    Section {
                        ForEach(Array(shortages.enumerated()), id: \.element.id) { index, req in
                            sheetRow(index, of: shortages.count) {
                                shortageRow(req)
                            }
                        }
                    } header: {
                        // Danger, unlike the advisory warnings elsewhere: this one
                        // blocks creation rather than merely cautioning.
                        HoneyLedgerFieldNote(
                            shortageMessage(count: shortages.count),
                            tint: .danger,
                            font: .subheadline.weight(.semibold)
                        )
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                    }
                }

                Section {
                    sheetRow(0, of: 1) {
                        HoneyLedgerField("Batch code") { focus in
                            TextField("Batch code", text: $model.code, prompt: Text(model.suggestedCode).foregroundStyle(Color.inkFaint))
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .fontDesign(.monospaced)
                                .focused(focus)
                        }
                    }
                } header: {
                    HoneyLedgerSectionLabel("Identification")
                } footer: {
                    if codeIsTaken {
                        BatchCodeDuplicateWarning()
                    }
                }

                if let estimate = model.cureEstimate {
                    cureSection(estimate)
                }
            }
            .navigationTitle("Create Batch")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle("Create Batch")
            .ledgerBackground()
            .task(id: existingCodes) {
                model.suggestCode(existingCodes: existingCodes)
            }
            .onReceive(NotificationCenter.default.publisher(for: .duplicatesMerged)) { _ in
                model.resolveMergedRows(in: context)
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
            .interactiveDismissDisabled(model.hasChanges)
        }
    }

    private func sheetRow<Content: View>(
        _ index: Int,
        of count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content().ledgerSheetRow(position: .position(index: index, count: count))
    }

    private func shortageMessage(count: Int) -> String {
        let text = AttributedString(
            localized: "Not enough stock for ^[\(count) ingredient](inflect: true). Reduce the batch count or restock."
        )
        return String(text.characters)
    }

    private func shortageRow(_ req: BatchRequirement) -> some View {
        let need = amountText(req.required, unit: req.unit)
        let have = amountText(req.available, unit: req.unit)
        let shortfall = amountText(req.shortfall, unit: req.unit)
        return HoneyLedgerLabeledRow(req.ingredient.name, value: {
            // U+2212, which VoiceOver would read as "minus"; the row's label
            // says "short" instead.
            Text.honeyLedgerFigure("\u{2212}\(shortfall)", numberColor: .danger)
        }, below: {
            Text("Need \(need) · have \(have)")
                .font(.footnote)
                .foregroundStyle(Color.inkSoft)
        })
        .accessibilityLabel("\(req.ingredient.name), short \(shortfall), need \(need), have \(have)")
    }

    /// Only for a solid bar: a batch of anything else never mentions a cure.
    private func cureSection(_ estimate: CureEstimate) -> some View {
        Section {
            sheetRow(0, of: 3) {
                HoneyLedgerSegmented(
                    "Process",
                    selection: $model.process,
                    options: SoapProcess.allCases.map { ($0, $0.label) }
                )
            }
            sheetRow(1, of: 3) {
                HoneyLedgerLabeledRow("Recommended") {
                    Text(estimate.band.rangeText)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.ink)
                }
            }
            sheetRow(2, of: 3) {
                Stepper(value: $model.cureDays, in: BatchCureLimits.days, step: 7) {
                    HoneyLedgerStepperLabel(
                        title: "Length",
                        value: CureLengthText.text(days: model.cureDays),
                        valueColor: .inkSoft
                    )
                }
                .accessibilityValue(CureLengthText.text(days: model.cureDays))
            }
        } header: {
            HoneyLedgerSectionLabel("Cure")
        } footer: {
            HoneyLedgerFooter(estimate.explanation)
        }
    }
}
