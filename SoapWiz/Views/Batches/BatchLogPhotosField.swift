import PhotosUI
import SwiftUI

/// The photos of a log entry being written: the ones it has, each with a
/// button to take it off, and a menu to add more from the camera or the
/// library.
///
/// Every path in hands its result to `ImageDownscaler` first, as `PhotoField`
/// does, so an original straight off the camera never reaches the model.
struct BatchLogPhotosField: View {
    let model: BatchLogEntryFormViewModel

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingLibrary = false
    @State private var showingCamera = false

    /// Set when a chosen file couldn't be turned into an image. Shown in place
    /// of the hint: otherwise nothing on screen says the pick was refused.
    @State private var problem: String?

    private static let side: CGFloat = 72
    private static let cornerRadius: CGFloat = 10

    private var hint: String {
        if let problem { return problem }
        if model.isLoadingPhotos { return "Loading\u{2026}" }
        if !model.canAddPhoto { return "An entry holds up to \(BatchLogEntryFormViewModel.maxPhotos) photos" }
        return "Take one or choose from your library"
    }

    var body: some View {
        if !model.photos.isEmpty {
            grid
        }
        addMenu
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Self.side), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(model.photos) { draft in
                cell(draft)
            }
        }
        .padding(.vertical, 4)
    }

    private func cell(_ draft: BatchLogPhotoDraft) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return shape
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: Self.side, height: Self.side)
            .overlay {
                if let image = draft.previewData.flatMap(UIImage.init(data:)) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            // After the overlay, so it crops the photo rather than only the well.
            .clipShape(shape)
            .overlay(alignment: .topTrailing) {
                Button {
                    model.removePhoto(draft)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.title3)
                }
                // Borderless, so each cell's button is its own tap target
                // rather than the form row claiming every tap.
                .buttonStyle(.borderless)
                .offset(x: 6, y: -6)
                .accessibilityLabel("Remove Photo")
            }
    }

    private var addMenu: some View {
        Menu {
            if CameraPicker.isSupported {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
            Button {
                showingLibrary = true
            } label: {
                Label("Choose Photos", systemImage: "photo.on.rectangle")
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Photos")
                        .foregroundStyle(.primary)
                    Text(hint)
                        .font(.subheadline)
                        .foregroundStyle(problem == nil ? .secondary : Color.red)
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
        .disabled(!model.canAddPhoto || model.isLoadingPhotos)
        .photosPicker(
            isPresented: $showingLibrary,
            selection: $pickerItems,
            maxSelectionCount: max(1, model.remainingPhotoSlots),
            matching: .images
        )
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { captured in
                Task { await add(captured) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await load(items) }
        }
    }

    /// Reads the picked items one at a time, in the order they were picked.
    /// `pickerItems` is cleared afterwards so the next visit to the library
    /// starts with nothing selected.
    private func load(_ items: [PhotosPickerItem]) async {
        model.isLoadingPhotos = true
        problem = nil
        defer {
            model.isLoadingPhotos = false
            pickerItems = []
        }
        var failures = 0
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let downscaled = await ImageDownscaler.hero(from: data) else {
                failures += 1
                continue
            }
            model.addPhoto(downscaled)
        }
        if failures > 0 {
            problem = failures == items.count
                ? "Couldn't open that. Try another photo."
                : "Some photos couldn't be opened."
        }
    }

    private func add(_ captured: UIImage) async {
        model.isLoadingPhotos = true
        problem = nil
        defer { model.isLoadingPhotos = false }
        guard let downscaled = await ImageDownscaler.hero(from: captured) else {
            problem = "Couldn't read that photo. Try another one."
            return
        }
        model.addPhoto(downscaled)
    }
}
