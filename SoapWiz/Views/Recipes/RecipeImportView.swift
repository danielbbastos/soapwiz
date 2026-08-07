import SwiftUI
import SwiftData
import PhotosUI

/// The paste screen: where a recipe from anywhere else becomes a recipe here.
struct RecipeImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]

    @State private var model = RecipeImportViewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var isReadingPhoto = false
    @State private var showingScanner = false
    @State private var textRevision = 0
    @State private var readingProblem: String?

    var onConfirm: ((PreparedRecipeImport) -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .input, .extracting:
                    inputForm
                case .review:
                    RecipeImportReviewView(model: model, inventory: inventory, onConfirm: confirm)
                case .failed(let error):
                    failureView(error)
                }
            }
            .navigationTitle("Import Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Import Recipe")
            .warmBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if model.phase == .input, !model.rawText.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear", role: .destructive) { replaceText(with: "") }
                    }
                }
            }
        }
        // A page-sized sheet on iPad. The default form sheet is shorter than
        // this screen, which pushed the action button and its note below the
        // fold with no hint they existed. `.fitted` is not an option: the
        // content is a Form, which has no finite intrinsic height, so fitting
        // to it collapses the sheet to almost nothing.
        .presentationSizing(.page)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await readText(from: item) }
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
            Section {
                RecipeTextInputView(text: $model.rawText, isEnabled: !model.isExtracting, revision: textRevision)
            } header: {
                Text("Recipe Text")
            } footer: {
                Text(inputFooter)
                    .foregroundStyle(readingProblem == nil ? .secondary : Color.orange)
            }
            .listRowBackground(Color.cardBackground)

            Section {
                sourceButtons
            }
            .disabled(model.isExtracting || isReadingPhoto)
            .listRowBackground(Color.cardBackground)

            Section {
                Button {
                    Task { await model.extract(inventory: inventory) }
                } label: {
                    if model.isExtracting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Reading the recipe\u{2026}")
                        }
                    } else {
                        Text("Read Recipe")
                    }
                }
                .disabled(!model.canExtract || isReadingPhoto)
            } footer: {
                Text("Your recipe is read on this device. Nothing is sent anywhere, and nothing is saved until you confirm.")
            }
            .listRowBackground(Color.cardBackground)
        }
    }

    /// One row rather than three. Stacked, these cost enough height to push the
    /// action button off an iPad form sheet entirely.
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
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Photo", systemImage: "photo")
            }
            .buttonStyle(.bordered)
            if DocumentScannerView.isSupported {
                Button {
                    showingScanner = true
                } label: {
                    Label("Scan", systemImage: "text.viewfinder")
                }
                .buttonStyle(.bordered)
            }
            Spacer(minLength: 0)
        }
        .buttonBorderShape(.capsule)
    }

    /// Says what will happen to an over-long paste before the user commits to
    /// it, rather than surprising them with a trimmed result afterwards.
    private var inputFooter: String {
        if isReadingPhoto { return "Reading the text in your photo\u{2026}" }
        if let readingProblem { return readingProblem }
        let count = model.rawText.count
        guard count > 0 else {
            return "Paste a recipe from a website, a forum or your notes. Oils, amounts and lye settings are enough."
        }
        guard count > RecipeTextSanitizer.defaultCharacterBudget else {
            return "\(count) characters."
        }
        return "\(count) characters — that's more than fits in one go, so the recipe will be picked out of it."
    }

    // MARK: - Failure

    private func failureView(_ error: RecipeImportError) -> some View {
        ContentUnavailableView {
            Label(error.errorDescription ?? "Import failed", systemImage: "text.badge.xmark")
        } description: {
            Text(error.recoverySuggestion ?? "")
        } actions: {
            Button("Back to Text") { model.returnToInput() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func confirm(_ prepared: PreparedRecipeImport) {
        onConfirm?(prepared)
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
