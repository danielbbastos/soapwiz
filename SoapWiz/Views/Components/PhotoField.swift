import PhotosUI
import SwiftUI

/// A form row for attaching one photo to a model.
///
/// The binding carries the *display-sized* image: every path into this view
/// hands its result to `ImageDownscaler` first, so an original straight off the
/// camera never reaches the caller, let alone the store. That keeps the resizing
/// decision in one place instead of at each call site, and means a caller only
/// has to derive its thumbnail.
struct PhotoField: View {
    @Binding var imageData: Data?

    var label: String = "Photo"

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
                apply(ImageDownscaler.hero(from: captured))
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
    private var well: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return shape
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: 56, height: 56)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "camera.fill")
                        .foregroundStyle(Color.accentColor.opacity(0.55))
                }
            }
            // After the overlay, so it crops the photo rather than only the well.
            .clipShape(shape)
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
        apply(ImageDownscaler.hero(from: data))
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
