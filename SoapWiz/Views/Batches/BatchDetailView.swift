import SwiftUI
import SwiftData

/// Read-only view of the immutable snapshot a `Batch` recorded at creation:
/// what was consumed, which purchases it drew from, and what it cost. Nothing
/// here recomputes against the live recipe or inventory — including whether
/// the batch was costed at all, which is the snapshot's `tracksInventory`.
/// The batch code, the cure length and the log are the exceptions: kept beside
/// the record, not part of it, and all can be changed from here.
struct BatchDetailView: View {
    @Environment(\.currencyCode) private var currencyCode
    @Query private var batches: [Batch]
    let batch: Batch

    @State private var editingCode = false
    @State private var codeCopied = false
    @State private var logPresentation = BatchLogPresentation()

    @ScaledMetric(relativeTo: .body) private var costColumnWidth: CGFloat = 72

    private func formatCurrency(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    private func amountText(_ amount: Double, unit: String) -> String {
        "\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
    }

    private var sortedLineItems: [BatchLineItem] {
        BatchHistoryViewModel.sortedLineItems(of: batch)
    }

    var body: some View {
        List {
            summarySection

            if batch.cureDays > 0 {
                BatchCureSection(batch: batch)
            }

            BatchLogSection(batch: batch, presentation: $logPresentation)

            consumedSection

            recipeSection
        }
        .readableWidth()
        .navigationTitle(batch.recipeName)
        .navigationBarTitleDisplayMode(.inline)
        .honeyLedgerInlineTitle(batch.recipeName)
        .ledgerBackground()
        .sheet(isPresented: $editingCode) {
            BatchCodeEditSheet(batch: batch)
        }
        .batchLogPresentations($logPresentation, batch: batch)
        .task(id: codeCopied) {
            guard codeCopied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            codeCopied = false
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        let costPerBatch = batch.batchCount > 1 ? BatchHistoryViewModel.costPerBatch(of: batch) : nil
        let count = 3 + (batch.tracksInventory ? 1 : 0) + (costPerBatch == nil ? 0 : 1)
        let isDuplicate = BatchCodeGenerator.isTaken(batch.code, among: batches, excluding: batch)
        return Section {
            codeRow
                .ledgerSheetRow(position: .position(index: 0, count: count))
            HoneyLedgerLabeledRow("Made") {
                figure(batch.dateCreated.formatted(date: .abbreviated, time: .shortened))
            }
            .ledgerSheetRow(position: .position(index: 1, count: count))
            HoneyLedgerLabeledRow("Batches") {
                figure("\(batch.batchCount)")
            }
            .ledgerSheetRow(position: .position(index: 2, count: count))
            if batch.tracksInventory {
                HoneyLedgerLabeledRow("Total cost") {
                    figure(formatCurrency(batch.totalCost))
                }
                .ledgerSheetRow(position: .position(index: 3, count: count))
                if let costPerBatch {
                    HoneyLedgerLabeledRow("Cost per batch") {
                        figure(formatCurrency(costPerBatch))
                    }
                    .ledgerSheetRow(position: .position(index: 4, count: count))
                }
            }
        } header: {
            HoneyLedgerOrnament()
                // The List's first-header inset leaves the ornament lower than
                // centred; the List clamps this negative padding, so -10 moves
                // it up about 7pt.
                .padding(.top, -10)
        } footer: {
            if isDuplicate || !batch.tracksInventory {
                VStack(alignment: .leading, spacing: 8) {
                    if isDuplicate {
                        BatchCodeDuplicateWarning()
                    }
                    if !batch.tracksInventory {
                        HoneyLedgerFooter("Made without inventory tracking, so no cost was recorded.")
                    }
                }
            }
        }
    }

    private func figure(_ value: String) -> some View {
        Text(value)
            .font(.body.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Color.ink)
    }

    /// Two buttons in one row, so both are borderless: a list row otherwise
    /// takes the whole row as the tap target of whichever button comes first.
    private var codeRow: some View {
        HStack {
            Text("Batch code")
                .foregroundStyle(Color.ink)
            Spacer(minLength: 8)
            HStack(spacing: 16) {
                Text(BatchHistoryViewModel.displayCode(of: batch))
                    .font(.body.weight(.medium))
                    .fontDesign(.monospaced)
                    .foregroundStyle(Color.ink)
                    .textSelection(.enabled)
                let code = BatchCodeGenerator.trimmed(batch.code)
                if !code.isEmpty {
                    Button {
                        UIPasteboard.general.string = code
                        codeCopied = true
                    } label: {
                        Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(Color.amberText)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy Batch Code")
                }
                Button {
                    editingCode = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(Color.amberText)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit Batch Code")
            }
        }
    }

    // MARK: - Consumed

    private var consumedSection: some View {
        let items = sortedLineItems
        return Section {
            ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { index, item in
                lineItemRow(item)
                    .ledgerSheetRow(position: .position(index: index, count: items.count))
            }
        } header: {
            HoneyLedgerSectionLabel("Consumed")
        }
    }

    private func lineItemRow(_ item: BatchLineItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.ingredientName)
                    .foregroundStyle(Color.ink)
                Spacer()
                Text(amountText(item.amountConsumed, unit: item.unit))
                    .foregroundStyle(Color.inkSoft)
                    .monospacedDigit()
                if item.cost > 0 {
                    Text(formatCurrency(item.cost))
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.ink)
                        .frame(width: costColumnWidth, alignment: .trailing)
                }
            }
            ForEach(item.draws.indices, id: \.self) { index in
                let draw = item.draws[index]
                let unitPrice = draw.pricePerUnit.unitPriceFormatted(currencyCode: currencyCode)
                HStack {
                    Text(draw.purchaseBadge.isEmpty ? "No lot" : "Lot \(draw.purchaseBadge)")
                    Spacer()
                    Text("\(amountText(draw.amountDrawn, unit: item.unit)) @ \(unitPrice)/\(item.unit)")
                        .monospacedDigit()
                    Text(formatCurrency(draw.cost))
                        .monospacedDigit()
                        .frame(width: costColumnWidth, alignment: .trailing)
                }
                .font(.footnote)
                .foregroundStyle(Color.inkSoft)
            }
        }
    }

    // MARK: - Recipe

    private var recipeSection: some View {
        Section {
            Group {
                if let recipe = batch.recipe {
                    NavigationLink(value: recipe) {
                        Label("Open recipe", systemImage: "function")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.amberText)
                    }
                } else {
                    Label("The original recipe no longer exists.", systemImage: "function")
                        .foregroundStyle(Color.inkSoft)
                }
            }
            .ledgerSheetRow(position: .only)
        }
    }
}
