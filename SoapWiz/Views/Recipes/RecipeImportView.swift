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
            }
        }
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
                onCancel: { showingScanner = false }
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Input

    private var inputForm: some View {
        Form {
            Section {
                RecipeTextInputView(text: $model.rawText, isEnabled: !model.isExtracting)
            } header: {
                Text("Recipe Text")
            } footer: {
                Text(inputFooter)
            }
            .listRowBackground(Color.cardBackground)

            Section {
                // The system's own paste button: the tap is the authorisation, so
                // it reads the clipboard without the "would like to paste from"
                // alert that a bare `UIPasteboard.general.string` triggers.
                PasteButton(payloadType: String.self) { strings in
                    guard let pasted = strings.first(where: { !$0.isEmpty }) else { return }
                    append(pasted)
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Read from a Photo", systemImage: "photo")
                }
                if DocumentScannerView.isSupported {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan a Printed Recipe", systemImage: "text.viewfinder")
                    }
                }
                if !model.rawText.isEmpty {
                    Button(role: .destructive) {
                        model.rawText = ""
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
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

    /// Says what will happen to an over-long paste before the user commits to
    /// it, rather than surprising them with a trimmed result afterwards.
    private var inputFooter: String {
        if isReadingPhoto { return "Reading the text in your photo\u{2026}" }
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
              let image = UIImage(data: data) else { return }
        await readText(from: [image])
    }

    private func readText(from images: [UIImage]) async {
        isReadingPhoto = true
        defer { isReadingPhoto = false }
        var pages: [String] = []
        for image in images {
            guard let text = try? await RecipeImageTextRecogniser.recogniseText(in: image), !text.isEmpty else { continue }
            pages.append(text)
        }
        guard !pages.isEmpty else { return }
        append(pages.joined(separator: "\n"))
    }

    /// Tidies whatever arrives before it lands in the box. OCR in particular
    /// returns runs of blank lines, which show up as dead space the user can
    /// neither see nor delete easily.
    private func append(_ text: String) {
        let addition = RecipeTextSanitizer.tidiedForEditing(text)
        guard !addition.isEmpty else { return }
        model.rawText = model.rawText.isEmpty ? addition : "\(model.rawText)\n\(addition)"
    }
}
