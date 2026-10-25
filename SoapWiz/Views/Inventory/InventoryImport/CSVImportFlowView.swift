import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The spreadsheet import, from picking the file to the result: start, column
/// mapping, review, then a summary. Nothing is saved until the review screen
/// confirms.
struct CSVImportFlowView: View {
    @Environment(\.dismiss) private var dismiss
    /// Every ingredient, hidden ones included: a row naming a hidden
    /// ingredient adds to it rather than creating a duplicate.
    @Query private var inventory: [Ingredient]

    @State private var model = CSVImportFlowViewModel()
    @State private var showingFilePicker = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .honeyLedgerInlineTitle(title)
                .ledgerBackground()
                .toolbar { toolbar }
                .interactiveDismissDisabled(model.isPastStart)
        }
        .fitsSheetToContent()
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]
        ) { result in
            Task { await model.open(result) }
        }
    }

    private var title: String {
        switch model.phase {
        case .start, .failed: String(localized: "Spreadsheet import")
        case .reading, .mapping: String(localized: "Columns")
        case .building, .review: String(localized: "Review")
        case .finished: String(localized: "Imported")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .start:
            startForm
        case .reading:
            progress("Reading the file…")
        case .mapping(let mapping):
            CSVMappingView(model: mapping)
        case .building:
            progress("Matching rows…")
        case .review(let review):
            InventoryImportReviewView(model: review, onFinished: { _ in model.finish() })
        case .finished(let summary):
            finished(summary)
        case .failed(let message):
            failed(message)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch model.phase {
        case .finished:
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        case .mapping(let mapping):
            cancelItem
            ToolbarItem(placement: .confirmationAction) {
                Button("Continue") {
                    Task { await model.continueToReview(inventory: inventory) }
                }
                .disabled(!mapping.canContinue)
            }
        case .review:
            cancelItem
            ToolbarItem(placement: .navigation) {
                Button("Columns") { model.backToMapping() }
            }
        case .start, .reading, .building, .failed:
            cancelItem
        }
    }

    private var cancelItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
    }

    // MARK: - Phases

    private var startForm: some View {
        Form {
            Section {
                Text(
                    "Bring your ingredients and stock across from a spreadsheet or another app’s export. "
                    + "You’ll check every row before anything is saved."
                )
                .foregroundStyle(Color.ink)
                .ledgerSheetRow(position: .first)
                HoneyLedgerActionRow("Choose file", systemImage: "doc") { showingFilePicker = true }
                    .ledgerSheetRow(position: .middle)
                ShareLink(
                    item: CSVImportSample(),
                    preview: SharePreview("SoapWiz Inventory Sample.csv")
                ) {
                    HoneyLedgerActionLabel("Get a sample file", systemImage: "square.and.arrow.up", isPrimary: false)
                }
                .ledgerSheetRow(position: .last)
            }
            Section {
                ForEach(Array(InventoryImportField.allCases.enumerated()), id: \.element) { index, field in
                    Text(field.label)
                        .foregroundStyle(Color.ink)
                        .ledgerSheetRow(position: .position(index: index, count: InventoryImportField.allCases.count))
                }
            } header: {
                HoneyLedgerSectionLabel("Which columns work")
            } footer: {
                HoneyLedgerFooter(
                    "Only Name is required. A quantity can include its unit, like “500 g”. "
                    + "Give either a total price or a price per unit."
                )
            }
        }
        .environment(\.defaultMinListRowHeight, 48)
    }

    private func progress(_ label: LocalizedStringKey) -> some View {
        ProgressView(label)
            .foregroundStyle(Color.inkSoft)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func finished(_ summary: String) -> some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(Color.success)
                        .accessibilityHidden(true)
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(Color.ink)
                }
                .padding(.vertical, 4)
                .ledgerSheetRow(position: .only)
            } footer: {
                HoneyLedgerFooter("You’ll find them in your inventory.")
            }
        }
        .environment(\.defaultMinListRowHeight, 48)
    }

    private func failed(_ message: String) -> some View {
        HoneyLedgerEmptyState(
            "Can’t import this file",
            systemImage: "exclamationmark.triangle",
            description: "\(message)"
        ) {
            Button("Choose another file") {
                model.restart()
                showingFilePicker = true
            }
            .fontWeight(.semibold)
            .foregroundStyle(Color.amberText)
        }
    }
}

#if DEBUG
#Preview("Start") {
    CSVImportFlowView()
        .modelContainer(for: Ingredient.self, inMemory: true)
}
#endif
