import SwiftUI
import SwiftData
import PhotosUI

/// The paste screen: where a recipe from anywhere else becomes a recipe here.
struct RecipeImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FreeTierGateEnvironment private var freeTier
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @Query(sort: \RecipeCollection.name) private var collections: [RecipeCollection]
    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]

    @State private var model = RecipeImportViewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var isReadingPhoto = false
    @State private var showingScanner = false
    @State private var showingFilePicker = false
    @State private var textRevision = 0
    @State private var readingProblem: String?
    @State private var hasOpenedFile = false
    @State private var confirmedFit: FreeTierImportFit?
    @State private var textBoxHeight = Self.minimumTextBoxHeight

    /// About seven lines. Below this the box stops shrinking and the form
    /// scrolls instead.
    private static let minimumTextBoxHeight: CGFloat = 160

    /// A file handed in from another app, opened as soon as the sheet appears so
    /// it lands on the exact-import review. `nil` for the in-app path, which
    /// starts on the input screen.
    var fileURL: URL?

    var onConfirm: ((PreparedRecipeImport) -> Void)?

    /// A free user's import leaves collection names unmatched, so nothing it
    /// brings in gets filed.
    private var fileableCollections: [RecipeCollection] {
        freeTier.gate.allows(.collections) ? collections : []
    }

    /// Called with the recipes an exact import added, so the caller can dismiss
    /// and show them.
    var onImported: (([Recipe]) -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .input:
                    inputForm
                case .extracting:
                    RecipeImportProgressView(draft: model.streamingDraft, status: model.extractionStatus)
                case .review:
                    RecipeImportReviewView(model: model, inventory: inventory, onConfirm: confirm)
                case .exactReview:
                    if let plan = model.transferPlan {
                        RecipeTransferReviewView(
                            plan: plan,
                            fit: confirmedFit ?? freeTier.gate.importFit(for: plan, in: modelContext),
                            onUpgrade: freeTier.presentUpgrade,
                            onToggleRecipe: model.toggleRecipe,
                            onConfirm: confirmExactImport
                        )
                    }
                case .failed(let error):
                    RecipeImportFailureView(error: error, onBack: { model.returnToInput() })
                }
            }
            .navigationTitle("Import Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle("Import Recipe")
            .ledgerBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if model.phase == .input {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Read") {
                            Task {
                                await model.extract(
                                    inventory: inventory,
                                    collections: fileableCollections,
                                    recipes: recipes,
                                    context: modelContext
                                )
                            }
                        }
                        .disabled(!model.canExtract || isReadingPhoto)
                    }
                }
            }
            .interactiveDismissDisabled(model.hasChanges)
        }
        // A page-sized sheet on iPad, because the text box fills whatever
        // height is spare and a bigger sheet gives it room to write in.
        // `.fitted` is not an option: the content is a Form, which has no
        // finite intrinsic height, so fitting to it collapses the sheet to
        // almost nothing.
        .presentationSizing(.page)
        .proUpgradeHost()
        .onReceive(NotificationCenter.default.publisher(for: .duplicatesMerged)) { _ in
            model.resolveMergedRows(in: modelContext, filesIntoCollections: freeTier.gate.allows(.collections))
        }
        // A handed-in file opens itself, once, skipping the input screen. The
        // guard survives the re-runs SwiftUI may make of this task; `openFile`
        // always leaves `.input` behind, so it can't fire twice.
        .task {
            guard let fileURL, !hasOpenedFile else { return }
            hasOpenedFile = true
            model.openFile(at: fileURL, inventory: inventory, collections: fileableCollections, recipes: recipes)
            ReceivedFileInbox.removeIfReceived(fileURL)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await readText(from: item) }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.soapWizRecipe]
        ) { result in
            switch result {
            case .success(let url):
                model.openFile(at: url, inventory: inventory, collections: fileableCollections, recipes: recipes)
            case .failure:
                readingProblem = "Couldn’t open that file. Try again."
            }
        }
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScannerView(
                onScan: { pages in
                    showingScanner = false
                    Task { await readText(from: pages) }
                },
                onCancel: { showingScanner = false },
                onFailure: { _ in
                    showingScanner = false
                    readingProblem = "The scanner stopped before it finished. Try again, or use a photo."
                }
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Input

    private var inputForm: some View {
        Form {
            // Always first: a shared SoapWiz file is the exact route, and it
            // works on every device. The text below it is the approximate one.
            Section {
                HoneyLedgerActionRow("Open Recipe File\u{2026}", systemImage: "doc.badge.plus") {
                    showingFilePicker = true
                }
                .ledgerSheetRow(position: .only)
            } header: {
                HoneyLedgerSectionLabel("Shared From SoapWiz")
            } footer: {
                HoneyLedgerFooter("A .soapwizrecipe file comes back exactly as it was sent, however many recipes are in it.")
            }

            Section {
                RecipeTextInputView(
                    text: $model.rawText,
                    isEnabled: !model.isExtracting,
                    height: textBoxHeight,
                    revision: textRevision,
                    onClear: { replaceText(with: "") }
                )
                    .ledgerSheetRow(position: .only)
            } header: {
                HoneyLedgerSectionLabel(model.canReadFreeText ? "Recipe Text" : "Paste a Copied Recipe")
            } footer: {
                if readingProblem != nil {
                    HoneyLedgerFieldNote(inputFooter, tint: .warning)
                } else {
                    HoneyLedgerFooter(inputFooter)
                }
            }

            Section {
                sourceButtons
                    .ledgerSheetRow(position: .only)
            }
            .disabled(model.isExtracting || isReadingPhoto)
        }
        .environment(\.defaultMinListRowHeight, 48)
        // The text box takes whatever height the screen has spare, so the
        // form fills the sheet without scrolling, down to its minimum. The
        // spare height is the visible height less the content's; the box
        // changes by that much, which leaves nothing spare and settles.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let visible = geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
            return (visible - geometry.contentSize.height).rounded()
        } action: { _, spare in
            let fitted = max(Self.minimumTextBoxHeight, textBoxHeight + spare)
            if fitted != textBoxHeight { textBoxHeight = fitted }
        }
    }

    /// One row rather than three, to save height for the text box.
    private var sourceButtons: some View {
        HStack(spacing: 10) {
            // The system's own paste button: the tap is the authorisation, so
            // it reads the clipboard without the "would like to paste from"
            // alert that a bare `UIPasteboard.general.string` triggers.
            PasteButton(payloadType: String.self) { strings in
                guard let pasted = strings.first(where: { !$0.isEmpty }) else { return }
                append(pasted)
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            // The system draws this button's label white whatever it is told,
            // so it can't take the ledger's dark `onAmber` label. White on
            // amber is short of 4.5:1; kept anyway, because a button of our
            // own would have iOS ask permission on every paste.
            .tint(Color.amber)
            // Photo and Scan exist to turn a picture into text for the language
            // model to read. With no model to read it, they would produce a box
            // of OCR output and no way to do anything with it. Paste stays:
            // text copied out of SoapWiz carries its own payload and needs no
            // model at all.
            if model.canReadFreeText {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    RecipeImportSourceChip(title: "Photo", systemImage: "photo")
                }
                .buttonStyle(.plain)
                if DocumentScannerView.isSupported {
                    Button {
                        showingScanner = true
                    } label: {
                        RecipeImportSourceChip(title: "Scan", systemImage: "text.viewfinder")
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Says which path the text in the box will take, since they give very
    /// different results and the difference is invisible otherwise, and what
    /// will happen to an over-long paste before the user commits to it.
    private var inputFooter: String {
        if isReadingPhoto { return "Reading the text in your photo\u{2026}" }
        if let readingProblem { return readingProblem }
        let count = model.rawText.count
        guard count > 0 else {
            guard model.canReadFreeText else {
                return "Paste a recipe copied from SoapWiz with Copy Recipe, or open a shared file above. "
                    + Self.noFreeTextNote
            }
            return "Paste a recipe from a website, a forum or your notes. Oils, amounts and lye settings are enough. "
                + Self.freeTextNote
        }
        if model.textCarriesExactPayload {
            return "A SoapWiz recipe — this will come back exactly as it was sent, every setting, not just the oils."
        }
        if model.textIsSoapWizCopy {
            return "A recipe copied from SoapWiz, so it’s read as written. Nothing is saved until you confirm."
        }
        let readNote = model.canReadFreeText ? Self.freeTextNote : Self.noFreeTextNote
        let lengthNote = count > RecipeTextSanitizer.defaultCharacterBudget
            ? "\(count) characters — that's more than fits in one go, so the recipe will be picked out of it."
            : "\(count) characters."
        return "\(lengthNote) \(readNote)"
    }

    private static let freeTextNote = "It’s read on this device. Nothing is sent anywhere, and nothing is saved until you confirm."

    private static let noFreeTextNote = "Reading a recipe written by hand needs Apple Intelligence, which this device can’t use."

    // MARK: - Actions

    /// Stays on the review when the free tier's recipes are used up, rather
    /// than closing it to a form that can't be saved.
    private func confirm(_ prepared: PreparedRecipeImport) {
        freeTier.ifMayCreateRecipe(in: modelContext) {
            onConfirm?(prepared)
            dismiss()
        }
    }

    /// Writes the payload and leaves. Unlike the text path, this does not open
    /// the recipe form: the recipes are already exactly what the sender had.
    private func confirmExactImport() {
        confirmedFit = model.transferPlan.map { freeTier.gate.importFit(for: $0, in: modelContext) }
        guard let recipes = model.confirmExactImport(
            context: modelContext,
            categories: categories,
            gate: freeTier.gate
        ) else {
            confirmedFit = nil
            return
        }
        onImported?(recipes)
        dismiss()
    }

    /// OCR lands in the same editable field rather than going straight to
    /// extraction: a photographed page always has a misread character or two,
    /// and fixing it here is easier than correcting the recipe afterwards.
    private func readText(from item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            readingProblem = "Couldn't open that photo. Try another one."
            return
        }
        await readText(from: [image])
    }

    /// Says why a photo produced nothing. Failing quietly here is
    /// indistinguishable from the feature being broken: the spinner stops, the
    /// box is unchanged, and the user cannot tell whether the page had no text
    /// or something went wrong reading it.
    private func readText(from images: [UIImage]) async {
        isReadingPhoto = true
        readingProblem = nil
        defer { isReadingPhoto = false }

        var pages: [String] = []
        var failed = false
        for image in images {
            do {
                let text = try await RecipeImageTextRecogniser.recogniseText(in: image)
                if !text.isEmpty { pages.append(text) }
            } catch {
                failed = true
            }
        }

        guard !pages.isEmpty else {
            readingProblem = failed
                ? "Couldn't read that image. Try another photo, or type the recipe in."
                : "No text found in that image. Try a closer or sharper photo."
            return
        }
        append(pages.joined(separator: "\n"))
    }

    /// Tidies whatever arrives before it lands in the box. OCR in particular
    /// returns runs of blank lines, which show up as dead space the user can
    /// neither see nor delete easily.
    ///
    /// The combined result is tidied too, not just the addition: a second
    /// import lands against text that is already there, and the seam between
    /// them is exactly where a stray blank run would appear.
    private func append(_ text: String) {
        let addition = RecipeTextSanitizer.tidiedForEditing(text)
        guard !addition.isEmpty else { return }
        let combined = model.rawText.isEmpty ? addition : "\(model.rawText)\n\(addition)"
        replaceText(with: RecipeTextSanitizer.tidiedForEditing(combined))
    }

    /// The single funnel for writes the user did not type, so the field is
    /// always told to lay itself out again.
    private func replaceText(with newValue: String) {
        model.rawText = newValue
        textRevision += 1
        readingProblem = nil
    }
}
