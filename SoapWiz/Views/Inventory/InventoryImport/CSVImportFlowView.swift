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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model = CSVImportFlowViewModel()
    @State private var showingFilePicker = false

    /// Read by the leaving step's transition, so it is set a moment before the
    /// phase changes.
    @State private var isGoingBack = false

    var body: some View {
        NavigationStack {
            ZStack {
                content
                    .id(stepID)
                    .importTransition(.step(isGoingBack: isGoingBack))
            }
            .animation(InventoryImportMotion.animation(reduceMotion: reduceMotion), value: stepID)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle(title)
            .ledgerBackground()
            .toolbar { toolbar }
            .interactiveDismissDisabled(model.isPastStart)
        }
        .presentationSizing(.page)
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

    private var stepID: Int {
        switch model.phase {
        case .start: 0
        case .failed: 1
        case .reading: 2
        case .mapping: 3
        case .building: 4
        case .review: 5
        case .finished: 6
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
                    isGoingBack = false
                    Task { await model.continueToReview(inventory: inventory) }
                }
                .disabled(!mapping.canContinue)
            }
        case .review:
            ToolbarItem(placement: .navigation) {
                Button {
                    isGoingBack = true
                    Task {
                        await Task.yield()
                        model.backToMapping()
                    }
                } label: {
                    Label("Columns", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityLabel("Back to columns")
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
        .readableWidth()
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
        .readableWidth()
    }

    private func failed(_ message: String) -> some View {
        HoneyLedgerEmptyState(
            "Can’t import this file",
            systemImage: "exclamationmark.triangle",
            description: "\(message)"
        ) {
            Button("Choose another file") {
                isGoingBack = false
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
