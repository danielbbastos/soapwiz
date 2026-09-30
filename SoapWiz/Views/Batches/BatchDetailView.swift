import SwiftUI
import SwiftData

/// Read-only view of the immutable snapshot a `Batch` recorded at creation:
/// what was consumed, which purchases it drew from, and what it cost. Nothing
/// here recomputes against the live recipe or inventory — including whether
/// the batch was costed at all, which is the snapshot's `tracksInventory`.
/// The batch code and the log are the exceptions: a label and a diary kept
/// beside the record, not part of it, and both can be changed from here.
struct BatchDetailView: View {
    @Environment(\.currencyCode) private var currencyCode
    @Query private var batches: [Batch]
    let batch: Batch

    @State private var editingCode = false
    @State private var codeCopied = false
    @State private var logPresentation = BatchLogPresentation()

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
        Form {
            Section {
                codeRow
            } footer: {
                if BatchCodeGenerator.isTaken(batch.code, among: batches, excluding: batch) {
                    BatchCodeDuplicateWarning()
                }
            }
            .listRowBackground(Color.cardBackground)

            Section {
                LabeledContent("Recipe", value: batch.recipeName)
                LabeledContent("Date", value: batch.dateCreated.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Batches", value: "\(batch.batchCount)")
                if batch.tracksInventory {
                    LabeledContent("Total cost", value: formatCurrency(batch.totalCost))
                    if batch.batchCount > 1, let costPerBatch = BatchHistoryViewModel.costPerBatch(of: batch) {
                        LabeledContent("Cost per batch", value: formatCurrency(costPerBatch))
                    }
                }
            } footer: {
                if !batch.tracksInventory {
                    Text("Made without inventory tracking, so no cost was recorded.")
                }
            }
            .listRowBackground(Color.cardBackground)

            BatchLogSection(batch: batch, presentation: $logPresentation)
                .listRowBackground(Color.cardBackground)

            Section("Consumed") {
                ForEach(sortedLineItems) { item in
                    lineItemRow(item)
                }
            }
            .listRowBackground(Color.cardBackground)

            Section {
                if let recipe = batch.recipe {
                    NavigationLink(value: recipe) {
                        Label("Open recipe", systemImage: "function")
                    }
                } else {
                    Label("The original recipe no longer exists.", systemImage: "function")
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.cardBackground)
        }
        .readableWidth()
        .navigationTitle("Batch")
        .navigationBarTitleDisplayMode(.inline)
        .warmNavigationTitle("Batch")
        .warmBackground()
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

    /// Two buttons in one row, so both are borderless: a form row otherwise
    /// takes the whole row as the tap target of whichever button comes first.
    private var codeRow: some View {
        LabeledContent("Batch code") {
            HStack(spacing: 16) {
                Text(BatchHistoryViewModel.displayCode(of: batch))
                    .monospacedDigit()
                    .textSelection(.enabled)
                let code = BatchCodeGenerator.trimmed(batch.code)
                if !code.isEmpty {
                    Button {
                        UIPasteboard.general.string = code
                        codeCopied = true
                    } label: {
                        Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy Batch Code")
                }
                Button {
                    editingCode = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit Batch Code")
            }
        }
    }

    private func lineItemRow(_ item: BatchLineItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.ingredientName)
                Spacer()
                Text(amountText(item.amountConsumed, unit: item.unit))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if item.cost > 0 {
                    Text(formatCurrency(item.cost))
                        .monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                }
            }
            ForEach(item.draws.indices, id: \.self) { index in
                let draw = item.draws[index]
                HStack {
                    Text(draw.purchaseBadge.isEmpty ? "No lot" : "Lot \(draw.purchaseBadge)")
                    Spacer()
                    Text("\(amountText(draw.amountDrawn, unit: item.unit)) @ \(formatCurrency(draw.pricePerUnit))/\(item.unit)")
                        .monospacedDigit()
                    Text(formatCurrency(draw.cost))
                        .monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }
}
