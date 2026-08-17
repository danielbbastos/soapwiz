import PhotosUI
import SwiftUI

/// A form row for attaching one photo to a model.
///
/// The binding carries the *display-sized* image: every path into this view
/// hands its result to `ImageDownscaler` first, so an original straight off the
/// camera never reaches the caller, let alone the store. That keeps the resizing
/// decision in one place instead of at each call site, and means a caller only
/// has to derive its thumbnail.
///
/// `placeholder` fills the well while there is no photo, so the row previews the
/// same stand-in the model is drawn with elsewhere — a camera glyph for a
/// recipe, the coloured initial for an ingredient. It defaults to the glyph.
struct PhotoField<Placeholder: View>: View {
    @Binding var imageData: Data?

    var label: String = "Photo"

    @ViewBuilder var placeholder: Placeholder

    @State private var pickerItem: PhotosPickerItem?
    @State private var showingLibrary = false
    @State private var showingCamera = false
    @State private var isLoading = false

    /// Set when a chosen file couldn't be turned into an image. Shown in place
    /// of the hint: the row otherwise looks exactly as it did before the tap,
    /// which is indistinguishable from the picker being broken.
    @State private var problem: String?

    private var image: UIImage? {
        imageData.flatMap(UIImage.init(data:))
    }

    var body: some View {
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
                Label("Choose Photo", systemImage: "photo.on.rectangle")
            }
            if imageData != nil {
                Divider()
                Button(role: .destructive) {
                    imageData = nil
                    problem = nil
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
            }
        } label: {
            rowLabel
        }
        .tint(.primary)
        // The picker is presented by the modifier rather than by a `PhotosPicker`
        // inside the menu, so that opening it is a plain menu action like the
        // other two rather than a control nested in a control.
        .photosPicker(isPresented: $showingLibrary, selection: $pickerItem, matching: .images)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { captured in
                // The task starts on the main actor on purpose: everything before
                // the `await` is this view's own state, and the downscale hops off
                // by itself.
                Task { await downscale(captured) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 12) {
            well
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(.primary)
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(problem == nil ? .secondary : Color.red)
            }
            Spacer()
            // An action menu, not a picker: the up/down chevrons this project
            // uses elsewhere promise a list of values to choose between, and
            // this row takes a photo, replaces one or removes one.
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var hint: String {
        if let problem { return problem }
        if isLoading { return "Loading\u{2026}" }
        return imageData == nil ? "Add a photo" : "Change or remove"
    }

    /// A fixed square whether or not there is a photo, so the row is the same
    /// height either way and choosing one doesn't shift the fields around it.
    @ViewBuilder
    private var well: some View {
        if let image {
            let shape = RoundedRectangle(cornerRadius: PhotoFieldWell.cornerRadius, style: .continuous)
            shape
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: PhotoFieldWell.side, height: PhotoFieldWell.side)
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                // After the overlay, so it crops the photo rather than only the well.
                .clipShape(shape)
        } else {
            placeholder
                .frame(width: PhotoFieldWell.side, height: PhotoFieldWell.side)
        }
    }

    /// Reads the picked item as data and downscales it off the display path.
    /// `pickerItem` is cleared afterwards so picking the same photo twice in a
    /// row still fires `onChange`.
    private func load(_ item: PhotosPickerItem) async {
        isLoading = true
        problem = nil
        defer {
            isLoading = false
            pickerItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            problem = "Couldn't open that photo. Try another one."
            return
        }
        apply(await ImageDownscaler.hero(from: data))
    }

    /// Shrinks a freshly captured photo, keeping the row's "Loading…" hint up
    /// while it happens. The downscale is `@concurrent`, so the main actor is
    /// free to draw that hint rather than being blocked by the work it describes.
    private func downscale(_ captured: UIImage) async {
        isLoading = true
        problem = nil
        defer { isLoading = false }
        apply(await ImageDownscaler.hero(from: captured))
    }

    private func apply(_ downscaled: Data?) {
        guard let downscaled else {
            problem = "Couldn't read that photo. Try another one."
            return
        }
        problem = nil
        imageData = downscaled
    }
}

/// The well's metrics, shared with whatever a caller passes as the placeholder
/// so the two agree on the square the row reserves.
enum PhotoFieldWell {
    static let side: CGFloat = 56
    static let cornerRadius: CGFloat = 10
}

/// The default stand-in: a camera glyph on the app's accent, for a model with no
/// picture of its own to fall back on.
struct PhotoFieldCameraPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: PhotoFieldWell.cornerRadius, style: .continuous)
            .fill(Color.accentColor.opacity(0.12))
            .overlay {
                Image(systemName: "camera.fill")
                    .foregroundStyle(Color.accentColor.opacity(0.55))
            }
    }
}

extension PhotoField where Placeholder == PhotoFieldCameraPlaceholder {
    init(imageData: Binding<Data?>, label: String = "Photo") {
        self.init(imageData: imageData, label: label) {
            PhotoFieldCameraPlaceholder()
        }
    }
}
